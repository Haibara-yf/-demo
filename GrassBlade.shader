Shader "GrassSystem/Blade"
{
    Properties
    {
        [Header(Shape)]
        _TaperAmount ("Taper Amount", Float) = 0
        _CurvedNormalAmount("Curved Normal Amount", Range(0, 5)) = 1
        _p1Offset ("p1Offset", Float) = 1
        _p2Offset ("p2Offset", Float) = 1

        [Header(Shading)]
        _TopColor ("Top Color", Color) = (.25, .5, .5, 1)
        _BottomColor ("Bottom Color", Color) = (.25, .5, .5, 1)
        [Header(Color Variation)]
        _ColorVariation ("Colour Variation (per clump)", Range(0, 0.5)) = 0.15
        _GrassAlbedo("Grass albedo", 2D) = "white" {}
        _GrassGloss("Grass gloss", 2D) = "white" {}

        [Header(Wind Animation)]
        _WaveAmplitude("Wave Amplitude", Float) = 1
        _WaveSpeed("Wave Speed", Float) = 1
        _SinOffsetRange("Phase Variation", Range(0, 10)) = 0.3
        _PushTipForward("Push Tip Forward", Range(0, 2)) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Simple Grass Blade"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off

            HLSLPROGRAM
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "CubicBezier.hlsl"

            struct GrassBlade
            {
                float3 position;
                float rotAngle;
                float hash;
                float height;
                float width;
                float tilt;
                float bend;
                float3 surfaceNorm;
                float windForce;
                float facingBend;
                float colorSeed;
            };

            StructuredBuffer<GrassBlade> _GrassBlades;
            StructuredBuffer<int> Triangles;
            StructuredBuffer<float4> Colors;
            StructuredBuffer<float2> Uvs;

            float _TaperAmount;
            float _CurvedNormalAmount;
            float _p1Offset;
            float _p2Offset;
            float4 _TopColor;
            float4 _BottomColor;
            float _ColorVariation;

            float _WaveAmplitude;
            float _WaveSpeed;
            float _SinOffsetRange;
            float _PushTipForward;

            TEXTURE2D(_GrassAlbedo);
            SAMPLER(sampler_GrassAlbedo);
            TEXTURE2D(_GrassGloss);
            SAMPLER(sampler_GrassGloss);

            struct Attributes
            {
                uint vertexID : SV_VertexID;
                uint instanceID : SV_InstanceID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 bentNormal : TEXCOORD1;
                float3 flatNormal : TEXCOORD2;
                float2 uv : TEXCOORD3;
                float t : TEXCOORD4;
                float colorSeed : TEXCOORD5;
            };

            // 绕任意轴旋转的矩阵（叶片朝向和侧向弯曲都要用）
            float3x3 RotationAboutAxis(float angleRad, float3 axis)
            {
                axis = normalize(axis);

                float s, c;
                sincos(angleRad, s, c);

                float t = 1.0 - c;

                float x = axis.x;
                float y = axis.y;
                float z = axis.z;

                float xy = x * y;
                float xz = x * z;
                float yz = y * z;
                float xs = x * s;
                float ys = y * s;
                float zs = z * s;

                float m00 = t * x * x + c;
                float m01 = t * xy - zs;
                float m02 = t * xz + ys;

                float m10 = t * xy + zs;
                float m11 = t * y * y + c;
                float m12 = t * yz - xs;

                float m20 = t * xz - ys;
                float m21 = t * yz + xs;
                float m22 = t * z * z + c;

                return float3x3(
                    m00, m01, m02,
                    m10, m11, m12,
                    m20, m21, m22
                );
            }

            // 叶片根部固定在世界原点，靠顶点色和实例数据往外长
            float3 GetRootPoint()
            {
                return float3(0,0,0);
            }

            // 叶尖位置由高度和倾斜角决定：倾斜越大，水平的偏移越大
            float3 GetTipPoint(float height, float tilt)
            {
                float p3y = tilt * height;
                float p3x = sqrt(height * height - p3y * p3y);
                return float3(-p3x, p3y, 0);
            }

            // 三个控制点：中间两点按 bend 往两边掰，再加上风的相位偏移
            void BuildBezierControls(float3 p0, inout float3 p3, float bend, float hash, float windForce, out float3 p1, out float3 p2)
            {
                p1 = lerp(p0, p3, 0.33);
                p2 = lerp(p0, p3, 0.66);

                float3 bladeDir = normalize(p3 - p0);
                float3 bezCtrlOffsetDir = normalize(cross(bladeDir, float3(0,0,1)));

                p1 += bezCtrlOffsetDir * bend * _p1Offset;
                p2 += bezCtrlOffsetDir * bend * _p2Offset;

                float p2WindEffect = sin((_Time.y + hash * 2 * PI) * _WaveSpeed + 0.66 * 2 * PI * _SinOffsetRange) * windForce;
                p2WindEffect *= 0.66 * _WaveAmplitude;

                float p3WindEffect = sin((_Time.y + hash * 2 * PI) * _WaveSpeed + 1.0 * 2 * PI * _SinOffsetRange) * windForce + _PushTipForward * (1 - bend);
                p3WindEffect *= _WaveAmplitude;

                p2 += bezCtrlOffsetDir * p2WindEffect;
                p3 += bezCtrlOffsetDir * p3WindEffect;
            }

            // 顶点阶段：曲线取点 → 加宽度 → 法线修正 → 两次旋转 → 输出
            Varyings vert(Attributes input)
            {
                Varyings output;

                // 每根草的全部参数都在 buffer 里，顶点阶段直接取
                GrassBlade bladeData = _GrassBlades[input.instanceID];
                float bend = bladeData.bend;
                float height = bladeData.height;
                float tilt = bladeData.tilt;
                float hash = bladeData.hash;
                float windForce = bladeData.windForce;

                float3 p0 = GetRootPoint();

                float3 p3 = GetTipPoint(height, tilt);

                float3 p1 = float3(0,0,0);
                float3 p2 = float3(0,0,0);
                BuildBezierControls(p0, p3, bend, hash, windForce, p1, p2);

                // 这里不传顶点缓冲：用 SV_VertexID 反查三角形索引，再取颜色和 UV
                int meshIndex = Triangles[input.vertexID];
                float4 vertexColor = Colors[meshIndex];
                float2 uv = Uvs[meshIndex];

                float t = vertexColor.r;
                float3 curvePoint = CubicBezier(p0, p1, p2, p3, t);

                // 宽度沿叶片高度线性收窄，避免顶端太钝
                float width = bladeData.width * (1 - _TaperAmount * t);
                float sideSign = vertexColor.g * 2 - 1;
                float3 position = curvePoint + float3(0, 0, sideSign * width);

                float3 tangent = CubicBezierTangent(p0, p1, p2, p3, t);
                float3 normal = normalize(cross(tangent, float3(0,0,1)));

                float3 bentNormal = normal;
                bentNormal.z += sideSign * _CurvedNormalAmount;
                bentNormal = normalize(bentNormal);

                float yawAngle = bladeData.rotAngle;
                float facingBend = bladeData.facingBend;

                float3x3 yawMatrix = RotationAboutAxis(-yawAngle, float3(0,1,0));

                float3x3 facingMatrix = RotationAboutAxis(facingBend, normalize(tangent));
                position = position - curvePoint;
                normal = mul(facingMatrix, normal);
                bentNormal = mul(facingMatrix, bentNormal);
                position = mul(facingMatrix, position);

                position = position + curvePoint;
                normal = mul(yawMatrix, normal);
                bentNormal = mul(yawMatrix, bentNormal);
                position = mul(yawMatrix, position);

                position += bladeData.position;

                output.positionCS = TransformWorldToHClip(position);
                output.bentNormal = bentNormal;
                output.flatNormal = normal;
                output.positionWS = position;
                output.uv = uv;
                output.t = t;
                output.colorSeed = bladeData.colorSeed;

                return output;
            }

            // 片元阶段：双面法线 + 主光 + SH，颜色按簇种子做冷暖偏移
            half4 frag(Varyings input, bool frontFace : SV_IsFrontFace) : SV_Target
            {
                // 背面用反射法线，双面渲染时不会一整片发黑
                float3 shadingNormal = frontFace ? normalize(input.bentNormal) : -reflect(-normalize(input.bentNormal), normalize(input.flatNormal));

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));
                float3 viewDir = normalize(GetCameraPositionWS() - input.positionWS);

                float3 albedoMask = saturate(_GrassAlbedo.Sample(sampler_GrassAlbedo, input.uv));

                float4 grassCol = lerp(_BottomColor, _TopColor, input.t);

                float seed = input.colorSeed;
                float brightness = 1.0 + (seed - 0.5) * 2.0 * _ColorVariation;
                float3 warmTint = float3(1.0 + _ColorVariation * 1.2, 1.0, 1.0 - _ColorVariation * 1.6);
                float3 coolTint = float3(1.0 - _ColorVariation * 1.2, 1.0, 1.0 + _ColorVariation * 0.9);
                grassCol.rgb *= brightness * lerp(coolTint, warmTint, seed);

                float3 albedo = grassCol.rgb * albedoMask;

                float gloss = (1 - _GrassGloss.Sample(sampler_GrassGloss, input.uv).r)* 0.35;

                half3 GI = SampleSH(shadingNormal);

                BRDFData brdfData;
                half alpha = 1;

                InitializeBRDFData(albedo, 0, half3(1, 1, 1), gloss, alpha, brdfData);
                float3 directBRDF = DirectBRDF(brdfData, shadingNormal, mainLight.direction, viewDir) * mainLight.color;

                float3 finalColor = GI * albedo + directBRDF * (mainLight.shadowAttenuation * mainLight.distanceAttenuation);

                float4 outColor = float4(finalColor, grassCol.a);
                return half4(outColor);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/InternalErrorShader"
}
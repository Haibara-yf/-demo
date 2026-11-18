Shader "Unlit/Water"
{
    Properties
    {
        [Space(15)]
        [Header(Color)]
        [HDR]_ShallowColor("Shallow Color",Color) = (0.2,1,0.2,1)
        [HDR]_DeepColor("Deep Color",Color) = (0.2,0.2,1,1)

        _ShallowDistance("Shallow Distance",Float) = 3
        _DeepDistance("Deep Distance",Float) = 15
        _Density("Density",Range(0,1)) =1
        _DiffuseIntensity("Diffuse Intensity",Float) = 1

        [Space(15)]
        [Header(Normal)]
        _NoiseMap("Noise",2D) = "black"{}
        _NormalMap("Normal",2D) = "bump"{}
        _NormalMapScale("NormalMapScale",Range(0,2)) = 1
        _DetailNormalMap("Detail Normal",2D) = "bump"{}
        _DetailNormalMapScale("Detail Normal Map Scale",Range(0,2)) = 1
        _TBNVec("TBN Vec",Vector) = (1,1,1,1)

        [Space(15)]
        [Header(Specular)]
        [HDR]_SpecularColor("Specular Color",Color)=(1,1,1,1)
        _SpecularRange("Specular Range",Range(0,1)) = 0.5
        _SpecularIntensity("Specular Intensity",Range(0,5)) = 1
        _SepcularNormalMapIntensity("Sepcular Normal Map Intensity",Range(0,1)) =1
        _DiffuseNormalMapIntensity("Diffuse Normal Map Intensity",Range(0,1)) =1

        [Space(15)]
        [Header(Caustic)]
        [Toggle(USE_PROCEDURAL_CAUSTIC)] _UseProceduralCaustic("Use Procedural Caustic",Float) =1
        _CausticMap("Caustic Map",2D) ="black"{}
        _CausticFade("Caustic Fade",Range(0,1)) = 0.5
        _CausticUVScale("Procedural Caustic UVScale",Float) = 1
        _CausticIntensity("Caustic Intensity",Range(0,2)) = 1

        [Space(15)]
        [Header(SSR)]
        _SSRMaxSampleCount ("SSR Max Sample Count", Range(0, 64)) =64
        _SSRSampleStep ("SSR Sample Step", Range(4, 32)) = 4
        _SSRIntensity ("SSR Intensity", Range(0, 2)) = 1
        _SSRNormalDistortion("SSR Normal Distortion",Range(0,1)) = 0.15
        _SSPRDistortion("Distortion",Float) = 1
        _SSPRFresnelVec("SSPR Vex: pow scale bias",Vector) = (1,1,0,0)
        [KeywordEnum(SSR,SSPR,None)] _RefType("Reflection Type",Float) =0

        [Space(15)]
        [Header(CubeMap)]
        _CubeMap("Cube Map",Cube) = "Black"{}

        [Space(15)]
        [Header(SSS)]
        [HDR]_SSSColor("SSS Color",Color) = (0.2,0.2,0.2,1)
        _SSSDistance("_SSSDistance",Range(0,1)) = 0.5
        _SSSExp("_SSSExp",Range(0,1)) = 1
        _SSSIntensity("_SSSIntensity",Range(0,10)) = 1


        [Space(15)]
        [Header(Cloud)]
        [Toggle(USE_CLOUD_MAP)] _EnableCloudMap("Enable Cloud Map",Float) =0
        _CloudMap ("Cloud Map", 2D) = "Black" {}
        _CloudIntensity("Cloud Intensity",Range(0,1)) = 0.5
        _CloudMoveSpeed("Cloud Move Speed",Float) = 0.1
        _CloudColor("Cloud Color",Color) =(1,1,1,1)
        _WindDirection("Wind Direction",Vector)=(1,0,0,0)

        [Space(15)]
        [Header(Shadow)]
        [Toggle(USE_SHADOW)] _UseShadow("Receive Shadow",Float) =0
        _ShadowIntensity("Shadowm Intensity",Range(0,1)) = 0.8

        [Space(15)]
        [Header(Foam)]
        [Toggle(USE_FOAM)] _EnableFoam("Enable Foam",Float) =0
        [HDR]_FoamColor("Foam Color",Color)=(1,1,1,1)
        [Toggle] _EnableDynamicFoam("Enable Dynamic Foam",Float) = 1
        _FoamWidth("Foam Width",Range(0,1)) = 0.95
        _FoamSpeed("Foam Speed",Float) = 1
        _FoamFadeDistance("Foam Fade Distance",Range(0,1)) = 0.95
        _FoamNoiseMap ("Foam Noise(xy:uvScale zw:pow scale)", 2D) = "white" {}
        _FoamNoisePowScaleVec("Foam Noise Pow Scale",Vector) = (1,1,1,1)

        [Header(AntiTiling)]
        _AntiTilingStrength("Anti-Tiling Strength",Range(0,1)) = 0.7
        _AntiTilingScale("Anti-Tiling Layer Scale",Range(0.05,3)) = 0.37
        _AntiTilingWarp("Anti-Tiling UV Warp",Range(0,0.5)) = 0.08
        _AntiTilingRotate("Anti-Tiling Layer Rotate (Deg)",Range(0,360)) = 37

        [Header(Flow)]
        _FlowDir("Flow Direction (XY)",Vector) = (1, 0.35, 0, 0)
        _FlowSpeed("Flow Speed",Range(0,2)) = 0.18

        [Header(Ripple)]
        _RippleDuration("Ripple Duration",Range(0.2,6)) = 2.0
        _RippleExpandSpeed("Ripple Expand Speed",Range(0,10)) = 2.5
        _RippleBandFreq("Ripple Band Frequency",Range(0,80)) = 18
        _RippleBandWidth("Ripple Band Width",Range(0.05,3)) = 0.6
        _RippleAmplitude("Ripple Amplitude",Range(0,2)) = 0.6
        _RippleFoamAmount("Ripple Foam Amount",Range(0,1)) = 0.25
        _RippleNormalWarp("Ripple Normal Warp",Range(0,3)) = 0.6

        [Header(WindField)]
        _WindTex("Wind Noise",2D) = "gray" {}
        _WindStrength("Wind Strength",Range(0,2)) = 0.35
        _WindScale("Wind Scale",Range(0.0005,0.5)) = 0.01
        _WindSpeed("Wind Speed",Range(0,2)) = 0.1
        _WindNormalScale("Wind Normal Scale",Range(0,4)) = 1.0
    }
    CustomEditor "WaterWindGUI"

    SubShader
    {
        Tags { "Queue" = "Transparent"  "RenderPipeline" = "UniversalPipeline" "ShaderModel" = "4.5" }

        Pass
        {
            Name "StylizedWaterSSR"

            HLSLPROGRAM
            #pragma target 4.5

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #pragma shader_feature _ USE_SHADOW
            #pragma shader_feature _ USE_FOAM
            #pragma shader_feature _ USE_CLOUD_MAP
            #pragma shader_feature _ USE_PROCEDURAL_CAUSTIC

            #pragma shader_feature  _REFTYPE_SSR _REFTYPE_SSPR _REFTYPE_NONE
            //#pragma multi_compile _ RIPPLE_WIDE_RANGE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "TALighting.cginc"
            #include "Noise.cginc"
            //#define RIPPLE_DEBUG_RINGS 1


            float4 _DeepColor;
            float4 _ShallowColor;

            TEXTURE2D(_NoiseMap);SAMPLER(sampler_NoiseMap);
            TEXTURE2D(_NormalMap);SAMPLER(sampler_NormalMap);
            TEXTURE2D(_DetailNormalMap);SAMPLER(sampler_DetailNormalMap);
            TEXTURE2D(_CausticMap);SAMPLER(sampler_CausticMap);
            TEXTURECUBE(_CubeMap);SAMPLER(sampler_CubeMap);
            TEXTURE2D(_CloudMap);SAMPLER(sampler_CloudMap);
            TEXTURE2D(_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);

            TEXTURE2D(ssprRT);SAMPLER(sampler_ssprRT);
            TEXTURE2D(ssprBlurRT);SAMPLER(sampler_ssprBlurRT);
            TEXTURE2D(_PlanarReflectionTexture);SAMPLER(sampler_PlanarReflectionTexture);
            TEXTURE2D(_FoamNoiseMap);SAMPLER(sampler_FoamNoiseMap);

            float4 _FoamNoisePowScaleVec;
            float4 _FoamNoiseMap_ST;


            float4 _CausticMap_ST;
            float _CausticIntensity;
            float _CausticUVScale;
            float _CausticFade;

            float _Density;
            float _ShallowDistance;
            float _DeepDistance;

            float _FlowSpeed;
            float4 _FlowDir;
            float _AntiTilingRotate;
            float _AntiTilingWarp;
            float _AntiTilingScale;
            float _AntiTilingStrength;
            float _DetailNormalMapScale;
            float _NormalMapScale;
            float _DiffuseNormalMapIntensity;
            float _SepcularNormalMapIntensity;

            float _RippleNormalWarp;
            // float _RippleFoamScroll;   // foam drift, dropped: too noisy at grazing angles
            float _RippleFoamAmount;
            float _RippleAmplitude;
            float _RippleBandWidth;
            float _RippleBandFreq;
            float _RippleExpandSpeed;
            float _RippleDuration;
            TEXTURE2D(_WindTex);
            SAMPLER(sampler_WindTex);
            float _WindNormalScale;
            float _WindSpeed;
            float _WindScale;
            float _WindStrength;
            float4 _RippleSources[32];
            // float4 _RippleSources[16];   // 16 slots left a visible gap between ripples

            // 32 个槽位在拖拽快的时候还是会断成一截，环形队列的思路也想过，
            // 但会牵扯到 shader 里按时间排序，先放着。
            // 调试用：把槽位画成 gizmo 看有没有漏发（C# 那边有 OnDrawGizmosSelected）
            float4 _LightColor0;

            float _SSSIntensity;
            float _SSSExp;
            float _SSSDistance;
            float4 _SSSColor;

            float _CloudIntensity;
            float _CloudMoveSpeed;
            float _WaveColorIntensity;
            float4 _WindDirection;
            float4 _CloudMap_ST;

            float4 _SSPRFresnelVec;
            float _SSPRDistortion;
            float _SSRNormalDistortion;
            float _SSRIntensity;
            float4 _PlayerPosition;

            float _ShadowIntensity;
            float _DiffuseIntensity;

            float4 _FoamColor;
            float _EnableDynamicFoam;
            float _FoamFadeDistance;
            float _FoamSpeed;
            float _FoamWidth;

            float4 _SpecularColor;
            float _SpecularIntensity;
            float _SpecularRange;

            float4 _DetailNormalMap_ST;
            float4 _NormalMap_ST;
            float4 _NoiseMap_ST;

            float4 _TBNVec;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float4 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float4 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float4 screenUV: TEXCOORD1;
                float4 shadowCoord: TEXCOORD2;
                float3 normalWS: TEXCOORD3;
                float3 tangentWS: TEXCOORD4;
                float3 bitangentWS: TEXCOORD5;
                float2 uv: TEXCOORD6;
            };

            // 顶点阶段：法线 / 切线换到世界空间，顺手把 UV 和屏幕坐标算好
            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                output.positionCS = TransformObjectToHClip(input.positionOS);
                output.positionWS = TransformObjectToWorld(input.positionOS);
                output.screenUV  =  ComputeScreenPos(output.positionCS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.tangentWS = TransformObjectToWorldNormal(input.tangentOS);
                float sign = input.tangentOS.w * ( unity_WorldTransformParams.w >= 0.0 ? 1.0 : -1.0 );
				output.bitangentWS = cross( output.normalWS, output.tangentWS ) * sign;
                output.uv = input.uv.xy;


                return output;
            }


            // voronoi 用的哈希，返回一个伪随机点，扰动后当特征点位置
            float2 voronoihash5( float2 p )
            {

                p = float2( dot( p, float2( 127.1, 311.7 ) ), dot( p, float2( 269.5, 183.3 ) ) );
                return frac( sin( p ) *43758.5453);
            }


            // 裁剪空间坐标 → 屏幕 UV + 深度，SSR 和折射都要用
            void GetScreenInfo(float4 positionCS,out float3 screenPixelNdcZ)
            {
                positionCS.y *= _ProjectionParams.x;
                positionCS.xyz /= positionCS.w;
                positionCS.xy = positionCS*0.5+0.5;
                screenPixelNdcZ.xyz = positionCS.xyz;
            }

            // 采样相机深度图
            float GetDepth(float2 uv)
            {
                return SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
            }

            // 采样不透明场景颜色做折射
            float4 GetSceneColor(float2 uv)
            {
                return SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture,uv);
            }

            // 廉价次表面散射：把法线往光方向掰一点再算透光
            float CheapSSS(float3 N,float3 L,float3 V,float SSSDistance,float SSSExp,float SSSIntensity)
            {
                float3 fakeN = -normalize(lerp(N,L,SSSDistance));
                float sss = SSSIntensity * pow( saturate( dot(fakeN,V)),SSSExp);
                return max(0,sss);
            }

            // 屏幕空间坐标是否还在画面内，SSR 步进时越界就提前退出
            bool IsInClipView(float3 Ray)
            {
                if(Ray.z<0 || Ray.z>1 || Ray.x<0 || Ray.x>1 || Ray.y<0 || Ray.y>1)
                {
                    return false;
                }
                return true;
            }

            // 五角星形 voronoi
            float voronoi5( float2 v, float time, inout float2 id, inout float2 mr, float smoothness )
            {
                float2 n = floor( v );
                float2 f = frac( v );
                float F1 = 8.0;
                float F2 = 8.0; float2 mg = 0;
                for ( int j = -1; j <= 1; j++ )
                {
                    for ( int i = -1; i <= 1; i++ )
                    {
                        float2 g = float2( i, j );
                        float2 o = voronoihash5( n + g );
                        o = ( sin( time + o * 6.2831 ) * 0.5 + 0.5 ); float2 r = f - g - o;
                        float d = 0.5 * dot( r, r );
                        if( d<F1 ) {
                            F2 = F1;
                            F1 = d; mg = g; mr = r; id = o;
                        } else if( d<F2 ) {
                            F2 = d;
                        }
                    }
                }
                return (F2 + F1) * 0.5;
            }

            // 屏幕空间反射：沿反射方向按固定步长走
            float4 WaterSSR(float3 positionWS,float3 waterNormal=float3(0,1,0))
            {
                float3 V = ( GetWorldSpaceViewDir(positionWS));
                float4 positionCS = TransformWorldToHClip(positionWS);

                float SSRLength = 15;
                float FarSSRLength = 50;
                float MaxLingearStep = 32;

                float3 reflectDir = reflect(-V,waterNormal);
                float3 endWS = positionWS + reflectDir*SSRLength;
                float4 endPositionCS = TransformWorldToHClip(endWS);

                float3 farWS = positionWS + reflectDir*FarSSRLength;
                float4 farPositionCS = TransformWorldToHClip(farWS);

                float3 begin_ScreenPixelNdcZ , end_ScreenPixelNdcZ,far_ScreenPixelNdcZ;

                GetScreenInfo(positionCS,begin_ScreenPixelNdcZ);
                GetScreenInfo(endPositionCS,end_ScreenPixelNdcZ);
                GetScreenInfo(farPositionCS,far_ScreenPixelNdcZ);

                float3 Step = (end_ScreenPixelNdcZ-begin_ScreenPixelNdcZ)/MaxLingearStep;
                float3 Ray = begin_ScreenPixelNdcZ;
                bool isHit = false;
                float2 hitUV = (float2)0;

                float LastDepth =Ray.z;

                float4 SSRColor = 0;
                float isFar=0;

                float fade = pow(1-dot(normalize(V),waterNormal),5);


                UNITY_BRANCH if((far_ScreenPixelNdcZ).y<1)
                {
                    float farDepth =  GetDepth(far_ScreenPixelNdcZ.xy);

                    farDepth = LinearEyeDepth(farDepth,_ZBufferParams);

                    float playViewDepth = mul(unity_WorldToCamera,float4(_PlayerPosition.xyz,1));

                   UNITY_BRANCH if(abs(playViewDepth-farDepth)>SSRLength)
                    {
                        SSRColor =  GetSceneColor(far_ScreenPixelNdcZ.xy)*fade;
                    }
                    else
                    {
                        SSRColor.w =1;
                    }
                }


                UNITY_LOOP
                for (int n=1;n<MaxLingearStep;n++)
                {
                    Ray += Step;
                    UNITY_BRANCH if(Ray.z<0 || Ray.z>1 || Ray.x<0 || Ray.x>1 || Ray.y<0 || Ray.y>1)
                    {
                        break;
                    }

                    float Depth = GetDepth(Ray.xy);

                    if(Ray.z<Depth  && Depth<LastDepth)
                    {
                        isHit = true;
                        hitUV = Ray.xy;
                        break;
                    }
                    LastDepth =Ray.z;
                }

                if(isHit)
                {
                    SSRColor =  GetSceneColor(hitUV)*fade;
                }
                return  SSRColor;
            }

            // 主片元：法线扰动 → 风 → 交互波纹 → 反射 → 泡沫 → 焦散 → 次表面
            half4 frag(Varyings input) : SV_Target
            {
                float4 finalColor = 0;
                float3 positionWS = input.positionWS;
                float2 screenUV = input.screenUV.xy / input.screenUV.w;
                float3 V = normalize( _WorldSpaceCameraPos - positionWS);
                float3 L = normalize(_MainLightPosition.xyz);

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float shadow = lerp(_ShadowIntensity,1, mainLight.shadowAttenuation);

                float4 noise = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, input.positionWS.xz*0.1 + float2(-_Time.x*0.5,0) );

                float3 N = normalize(input.normalWS.xyz);
                float3 T = normalize(input.tangentWS.xyz);
                float3 B = normalize(input.bitangentWS.xyz);
                float3x3 TBN = float3x3(T*_TBNVec.x,B*_TBNVec.y,N*_TBNVec.z);

                float2 wuv = input.positionWS.xz;

                float  ang = radians(_AntiTilingRotate);
                float  cs  = cos(ang);
                float  sn  = sin(ang);
                float2x2 rotM = float2x2(cs, -sn, sn, cs);

                float2 fdir = normalize(_FlowDir.xy + float2(1e-5, 1e-5));
                float2 flow = fdir * (_Time.y * _FlowSpeed);

                float2 uvA = wuv * _NormalMap_ST.xy + flow;

                float2 uvB = mul(rotM, wuv * _NormalMap_ST.xy * _AntiTilingScale)
                           + flow * 0.85;

                uvB += (noise.xz - 0.5) * 2.0 * _AntiTilingWarp;

                float4 nA = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvA);
                float4 nB = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvB);

                float3 tA = UnpackNormalScale(nA, _NormalMapScale);
                float3 tB = UnpackNormalScale(nB, _NormalMapScale);

                float antW = saturate(noise.y * 1.7) * saturate(_AntiTilingStrength);

                float3 normalMap = normalize(lerp(tA, tB, antW));

                float4 rawNormalDetailMap = SAMPLE_TEXTURE2D(_DetailNormalMap, sampler_DetailNormalMap, wuv * _DetailNormalMap_ST.xy + float2(-_Time.x * 0.3, 0.0));
                float3 normalDetailMap = UnpackNormalScale(rawNormalDetailMap, _DetailNormalMapScale);

                normalMap = BlendNormal(normalDetailMap, normalMap);

                {
                    float2 wUV = input.positionWS.xz * _WindScale
                               + _Time.y * float2(1.0, 0.7) * _WindSpeed;

                    float w0 = SAMPLE_TEXTURE2D(_WindTex, sampler_WindTex, wUV).r;

                    float e  = 0.0015;
                    float wx = SAMPLE_TEXTURE2D(_WindTex, sampler_WindTex, wUV + float2(e, 0.0)).r;
                    float wz = SAMPLE_TEXTURE2D(_WindTex, sampler_WindTex, wUV + float2(0.0, e)).r;
                    float2 grad = float2(wx - w0, wz - w0) / e * 0.02;

                    float  theta = (w0 * 2.0 - 1.0) * 3.14159265;
                    float2 wdir  = float2(cos(theta), sin(theta));

                    float2 perturb = wdir * (w0 - 0.5) * 2.0 + grad;

                    float3 pW  = float3(perturb.x, 0.0, perturb.y);
                    float2 pTS = float2(dot(pW, T), dot(pW, B));
                    float3 windTS = normalize(float3(pTS * _WindStrength * _WindNormalScale, 1.0));
                    normalMap = BlendNormal(normalMap, windTS);
                }

                float rippleFoamMask = 0.0;

                // 32 次循环 × 逐像素，1440p 下这块大概 1.2ms，能接受。
                // 试过按距离做 early out，效果不明显，反而多了分支，撤了。
                for (int slotIndex = 0; slotIndex < 32; slotIndex++)
                {
                    float4 source = _RippleSources[slotIndex];
                    float  amplitude = source.w;
                    if (amplitude <= 0.0) continue;

                    float elapsed = _Time.y - source.z;
                    if (elapsed < 0.0 || elapsed > _RippleDuration) continue;

                    float2 normalWarp = normalMap.xy * _RippleNormalWarp;
                    float2 delta2D   = (input.positionWS.xz - source.xy) + normalWarp;
                    float  distanceToSource = length(delta2D);
                    float2 direction  = delta2D / max(distanceToSource, 1e-4);

                    float ringRadius = elapsed * _RippleExpandSpeed;
                    // 半径是线性推的，远看其实应该按 sqrt 走，现在半径大了之后
                    // 波前会变薄，看着有点像水面在"抖"，这块还没调好。
                    float bandOffset   = abs(distanceToSource - ringRadius);

                    // falloff = saturate(1.0 - bandOffset / _RippleBandWidth);   // ring never widens, looks flat
                    float falloff = saturate(1.0 - bandOffset / (_RippleBandWidth + ringRadius * 0.15));
                    falloff *= saturate(1.0 - elapsed / _RippleDuration);
                    falloff *= falloff;
                    // 乘两次是为了让环形边缘陡一点，但陡了之后有锯齿，Freq 高了更明显。

                    float waveHeight = sin(bandOffset * _RippleBandFreq - elapsed * 6.0) * falloff * _RippleAmplitude * amplitude;
                    // _RippleBandFreq 拉到 40 以上会有摩尔纹，材质里先压在 18。
                    // float waveHeight = cos(bandOffset * _RippleBandFreq - elapsed * 6.0) * falloff;   // softer crest, less punch

                    float3 directionWS = float3(direction.x, 0.0, direction.y);
                    float2 directionTS = float2(dot(directionWS, T), dot(directionWS, B));

                    float3 rippleNormalTS = normalize(float3(directionTS * waveHeight, 1.0));

                    normalMap = BlendNormal(normalMap, rippleNormalTS);
                    // 用 BlendNormal 而不是直接加，不然波纹会和原本的水面法线打架，边缘发黑。

                    rippleFoamMask += saturate(waveHeight) * _RippleFoamAmount * falloff * amplitude;
                    // 泡沫直接加会有点脏，强度先压到 0.25，等贴图重做再说。
                }

                normalMap = normalize(normalMap);

                normalMap = mul(normalMap,TBN);

                float ssprFresnel = pow(1-V.y + _SSPRFresnelVec.z,_SSPRFresnelVec.x)*_SSPRFresnelVec.y;
                float4 sspr = SAMPLE_TEXTURE2D(_PlanarReflectionTexture, sampler_PlanarReflectionTexture, screenUV + (normalMap.xz)*_SSPRDistortion );


                float4 Radiance = _LightColor0;
                float LightLum = Luminance(Radiance.xyz);

                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV);
                float3 depthWorldPosition = ComputeWorldSpacePosition(screenUV, depth, UNITY_MATRIX_I_VP);

                float depthDistance = length(depthWorldPosition - input.positionWS);
                float depthFade = saturate( depthDistance/_DeepDistance);
                finalColor = lerp(_ShallowColor,_DeepColor,depthFade);

                finalColor = lerp( finalColor,sspr, ssprFresnel);

                float2 distortionUV = (noise*2-1)*0.01*2;
                float4 sceneColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, screenUV +distortionUV );
                float distortionDistanceFade = saturate( depthDistance/_ShallowDistance);
                finalColor = lerp(sceneColor,lerp(sceneColor,finalColor,_Density),distortionDistanceFade);

                float NL = dot(lerp(float3(0,1,0),normalMap,_DiffuseNormalMapIntensity) ,L);
                float NL01 =  NL*0.5+0.5;
                float diffuse = lerp(0.25,1.2,NL01);
                finalColor *= diffuse*LightLum*_DiffuseIntensity;

                float3 H = normalize(L+V);
                float specular =  D_DistributionGGX(normalize( lerp(float3(0,1,0),normalMap,_SepcularNormalMapIntensity) ), H,_SpecularRange)*_SpecularIntensity;
                finalColor += specular*Radiance.xyzz*mainLight.shadowAttenuation;

                #ifdef USE_FOAM
                    float foamDistance = 1- saturate(depthDistance/2);
                    float foamDynamic = 0.5* step( _FoamWidth,frac(foamDistance - _Time.y*0.1*_FoamSpeed + noise.r*0.0225)) * foamDistance*foamDistance;
                    foamDynamic = _EnableDynamicFoam*foamDynamic* smoothstep( _FoamFadeDistance ,1,foamDistance);
                    float foamStatic =  0.5 *step( _FoamWidth,frac(foamDistance  + noise.r*0.02525)) * foamDistance*foamDistance;
                    float foam = max(foamDynamic,foamStatic);

                    float foamNoise = SAMPLE_TEXTURE2D(_FoamNoiseMap, sampler_FoamNoiseMap,positionWS.xz*_FoamNoiseMap_ST.xy);
                    foamNoise = saturate( pow(foamNoise,_FoamNoisePowScaleVec.x) *_FoamNoisePowScaleVec.y);

                    finalColor += foam*LightLum*_FoamColor*foamNoise* saturate(dot(N,V));
                #endif

                finalColor += rippleFoamMask * _FoamColor * LightLum;
                // TODO: 波纹碰到岸边应该碎掉，现在没有深度信息，直接穿过去了。
                // finalColor = lerp(finalColor, _FoamColor.rgb, rippleFoamMask * foam);

                #ifndef  USE_PROCEDURAL_CAUSTIC
                    float4 caustic = SAMPLE_TEXTURE2D(_CausticMap, sampler_CausticMap, depthWorldPosition.xz*0.2*_CausticMap_ST.xy+distortionUV*5);
                #else
                    float4 caustic =GetCaustic(depthWorldPosition*0.4*_CausticUVScale+distortionUV.xyy*5 + float3(0,_Time.x,0)).xyzz;
                #endif

                caustic *= smoothstep(_CausticFade,1, (1-distortionDistanceFade) )*_CausticIntensity*NL01;
                finalColor += caustic*LightLum* mainLight.shadowAttenuation;


                #ifdef USE_CLOUD_MAP
                    float2 cloudMapUV = positionWS.xz*_CloudMap_ST.xy*0.01 + _WindDirection.xy* _CloudMoveSpeed*_Time.y;
                    float cloudMap = SAMPLE_TEXTURE2D(_CloudMap,sampler_CloudMap,cloudMapUV).r;
                    float cloud = cloudMap * _CloudIntensity;
                    finalColor +=cloud;
                #endif


                float4 waterSSS = CheapSSS(N,L,V,_SSSDistance,_SSSExp,_SSSIntensity)*_SSSColor;

                finalColor += waterSSS;

                finalColor *= shadow;

                finalColor.a =1;
                return finalColor;

            }
            ENDHLSL

        }
    }
}

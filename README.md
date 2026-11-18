# 大世界渲染 Demo

> Unity URP · 程序化草地 / 交互水面 / GPU 鸟群 / SDF 体积云

一个把「地表植被 + 水面 + 生物 + 天空」四类大世界元素放在同一个场景里跑的实时渲染 Demo。
重点在**程序化生成**与**GPU 侧剔除**：草地全部由 Compute Shader 生成，CPU 不参与逐株创建，
绘制只有一次 `Graphics.DrawProceduralIndirect`。

---

## 目录

- [效果概览](#效果概览)
- [1. 程序化草地（核心）](#1-程序化草地核心)
- [2. 交互水面](#2-交互水面)
- [3. GPU 鸟群](#3-gpu-鸟群)
- [4. SDF 体积云](#4-sdf-体积云)
- [5. 演示模式](#5-演示模式)
- [6. 目录结构](#6-目录结构)
- [7. 运行方式](#7-运行方式)
- [8. 已知限制](#8-已知限制)

---

## 效果概览

| 模块 | 关键技术 | 实现位置 |
|---|---|---|
| **草地** | Compute 生成 + 视锥/距离剔除 + 间接绘制 + 程序化叶片 | `Scripts/Grass.cs`、`Compute/GrassCS.compute`、`Shaders/GrassBlade.shader` |
| **水面** | URP 风格化水体 + 全局数组交互波纹 | `water.shader`、`WaterRippleEmitter.cs` |
| **鸟群** | Compute Shader Boids 三规则 + 双缓冲 | `Boids.compute`、`GPUBoids.cs` |
| **体积云** | SDF 造型 + 3D Perlin-Worley 噪声 + 光线步进 | `SDFCloud.shader` |
| **扰动** | 角色经过草丛时按距离权重摆动 | `GrassPresser.cs` |

---

## 1. 程序化草地（核心）

### 1.1 生成管线

```
Compute Shader（每帧）
   └─ 每个线程负责一根草
        位置 → 分簇 → 贴地形 → 视锥剔除 → 距离剔除
        → 姿态 / 颜色 / 尺寸 / 风 / 扰动
        → AppendStructuredBuffer
              ↓
        Counter 写入 IndirectArguments
              ↓
Graphics.DrawProceduralIndirect（DrawCall = 1）
              ↓
Vertex Shader：按 SV_VertexID 反查三角形，贝塞尔曲线展开成叶片
```

**整条链路里 CPU 不碰任何草叶数据**，只负责每帧上传参数。

### 1.2 视锥剔除（GPU 端）

```hlsl
uint IsFrustumCulled(float3 worldPos)
{
    float4 clip = mul(_VP_MATRIX, float4(worldPos, 1));

    return (clip.z > clip.w
        || clip.z < 0
        || clip.x < -clip.w + _FrustumCullEdgeOffset
        || clip.x >  clip.w - _FrustumCullEdgeOffset
        || clip.y < -clip.w + _FrustumCullNearOffset
        || clip.y >  clip.w) ? 0 : 1;
}
```

- 直接把点变换到**裁剪空间**比边界，比逐平面点积便宜
- `_FrustumCullEdgeOffset` / `_FrustumCullNearOffset` 是**负偏移**，
  让剔除边界往里收一点 —— 否则屏幕边缘的草会突然整根消失（视觉上很跳）

### 1.3 距离剔除（概率式）

```hlsl
uint IsDistanceCulled(float3 worldPos, float hash)
{
    float d = distance(worldPos, _WSpaceCameraPos);
    float keep = 1 - smoothstep(_DistanceCullStartDist, _DistanceCullEndDist, d);
    keep = keep * (1 - _DistanceCullMinimumGrassAmount) + _DistanceCullMinimumGrassAmount;
    return hash > 1 - keep ? 1 : 0;
}
```

远处不是一刀切掉，而是**按概率丢草** —— 密度的过渡是渐变的，看不出硬边界。

### 1.4 间接绘制

```csharp
ComputeBuffer.CopyCount(bladesBuffer, drawArgsBuffer, sizeof(int));
Graphics.DrawProceduralIndirect(bladeMaterial, drawBounds, MeshTopology.Triangles,
    drawArgsBuffer, 0, null, null,
    UnityEngine.Rendering.ShadowCastingMode.Off, true, gameObject.layer);
```

- `AppendStructuredBuffer` 的 Counter 直接当实例数
- 草叶数量随剔除结果实时变化，**CPU 完全不知道这一帧画了多少根**

### 1.5 叶片形态

草叶不是模型，是**程序化贝塞尔曲线**：

```hlsl
float3 p0 = GetRootPoint();
float3 p3 = GetTipPoint(height, tilt);
GetP1P2P3(p0, p3, bend, hash, windForce, p1, p2);   // 两个控制点

float3 center = CubicBezier(p0, p1, p2, p3, t);     // t = 顶点色 R 通道（沿叶片高度）
float width  = blade.width * (1 - _TaperAmount * t);  // 沿高度收窄
float side   = vertexColor.g * 2 - 1;               // 左/右
position = center + float3(0, 0, side * width);
```

叶片网格的颜色通道被复用：

| 通道 | 含义 |
|---|---|
| `R` | 沿叶片的高度（0 = 根部，1 = 尖）|
| `G` | 左 / 右半边 |

这样做的好处：**同一份网格数据能做锥化、法线修正、渐变色，不用额外属性。**

### 1.6 分簇着色（Voronoi）

```hlsl
float3 clumpSample = ClumpTex.SampleLevel(samplerClumpTex, clumpUV, 0).xyz;
float  clumpIndex  = clumpSample.x;                       // 属于哪一簇
float2 clumpCenter = (clumpSample.yz + floor(clumpUV)) / _ClumpScale;
```

启动时用 Voronoi 材质 `Blit` 到 RenderTexture，再读回 Texture2D。
每簇共享：**朝向一致性**、**颜色种子**、**倾斜/弯曲基准值** —— 避免整片草像一块地毯。

### 1.7 风

```hlsl
float windValue = _LocalWindTex.SampleLevel(LinearRepeatSampler, worldXZ * _LocalWindScale
                                            + _Time * float2(1, 0.7) * _LocalWindSpeed, 0).r;
float windTheta = (windValue * 2 - 1) * PI;
```

噪声贴图 + 世界 UV 滚动 → 风向和风力都来自同一张噪声，相邻的草摆向一致，形成"阵风"。

### 1.8 角色扰动

```hlsl
float2 toInteractor = position.xz - _PresserPos.xz;
float  falloff = 1 - smoothstep(0, _PressRadius, length(toInteractor));

if (falloff > 0.001)
{
    float phase = bladeData.hash * 6.2831853;            // 每根草相位不同
    float t = _Time * _DisturbSpeed + phase;
    float sway = sin(t) * 0.7 + sin(t * 2.13 + 1.7) * 0.3;  // 双频叠加

    bladeData.bend += sway * falloff * _DisturbStrength;
    bladeData.tilt += sway * falloff * _DisturbStrength * 0.35;
}
```

**只改弯曲和倾斜，不改高度** —— 草是被"拨开"，而不是整体塌陷。

### 1.9 关键参数

| 参数 | 值 | 说明 |
|---|---|---|
| `bladeSpacing` | 0.125 m | 草叶间距 |
| `gridResolution` | 1600 | 网格边长，**总潜在草叶 = 1600² = 256 万** |
| 草区尺寸 | **200 × 200 m** | `resolution × spacing` |
| `clumpCount` | 100 | 分簇数量 |
| `distanceCullEndDistance` | 150 m | 超过后只剩 60% 密度 |

### 1.10 性能

| 项 | 值 |
|---|---|
| 绘制调用 | **1** |
| CPU 逐株处理 | **0**（全部在 GPU）|
| 草叶数据上传 | 每帧 1 次参数上传，无回读 |
| 实测帧率 | 待填 |

---

## 2. 交互水面

基于 TAPro Stylized Water 改造，**新增交互波纹系统**。

### 2.1 数据驱动，零额外 DrawCall

```csharp
Shader.SetGlobalVectorArray("_RippleSources", _rippleSlots);   // 32 × float4
```

```hlsl
float4 _RippleSources[32];   // (worldX, worldZ, startTime, strength)
```

C# 只负责写数组，Shader 逐像素解析并**提前跳过空槽**（`strength <= 0`）。
水面本身不需要额外的相机、RenderTexture 或粒子。

### 2.2 波纹形态

```hlsl
float elapsed   = _Time.y - source.z;
float ringRadius = elapsed * _RippleExpandSpeed;
float bandOffset = abs(distanceToSource - ringRadius);
float falloff    = saturate(1 - bandOffset / (_RippleBandWidth + ringRadius * 0.15));
float waveHeight = sin(bandOffset * _RippleBandFreq - elapsed * 6.0) * falloff;

// 在切线空间做高度场混合，而不是直接把法线相加
float3 rippleNormalTS = normalize(float3(directionTS * waveHeight, 1));
normalMap = BlendNormal(normalMap, rippleNormalTS);
```

关键点：用 `BlendNormal` 做**高度场混合**，波前受原本水面法线扰动，
波纹不是"贴"在水面上，而是和水面互相影响。

### 2.3 鼠标交互

按下起一圈，按住拖动沿路径连续补圈：

```csharp
if (stepDistance < dragStepDistance) return;   // 距离节流
if (elapsedSinceEmit < dragMinPeriod) return;  // 时间节流
```

快速划过时在起点和终点之间**插值补圈**，避免拖出一截一截的断点。

---

## 3. GPU 鸟群

```hlsl
// 三规则：分离 / 对齐 / 聚合
float3 separation = ...;   // 远离过近邻居
float3 alignment  = ...;   // 朝邻居平均速度对齐
float3 cohesion   = ...;   // 朝邻居中心靠拢
velocity += Limit(desired - velocity, _MaxForce);   // 转向力限幅
```

- `RWStructuredBuffer` 双缓冲乒乓计算，避免读写冲突
- `DrawMeshInstancedIndirect` 绘制
- 规模：**512 ~ 2048 只**（`GPUBoids` 预设：椋鸟群 / 大雁编队 / 受惊炸开 / 蜂群 / 迁徙）

---

## 4. SDF 体积云

```hlsl
// 3D SDF 造型
float sdf = sdSphere(p + offset, 0.1);
sdf = opSmoothUnion(sdf, sdTorus(p, float2(0.2, 0.05)), 0.1);

// Perlin-Worley 噪声扰动密度
float density = saturate(_SDFTexture.Sample(...).r - noise * _PerlinWorlyNoiseScale);

// 光线步进 + 吸收光照
```

- 形状用 SDF 布尔运算拼，再用 3D Perlin-Worley 噪声"侵蚀"出细节
- 光照用 `_LightAbsorption` 近似 Beer-Lambert 吸收

---

## 5. 演示模式

为了方便展示，做了两个固定/半固定镜头的演示模式（菜单一键切换）：

| 菜单 | 模式 | 说明 |
|---|---|---|
| `Tools → 草地 → ① 开启视锥剔除演示` | **视锥剔除** | 草的相机跟着玩家，主相机升到高空俯视 —— 可以直接看到草只长在视锥里（梯形） |
| `Tools → 草地 → ③ 开启草丛扰动演示` | **草丛扰动** | 草的相机固定、主相机鼠标轨道控制 —— 人走进草丛时草被拨开 |

两者的核心区别在**草的生成相机是否移动**：

```
视锥演示：草相机跟随 → 草区跟着人移动 → 俯视看是"流动的梯形"
扰动演示：草相机固定 → 草是世界里固定的一片 → 只有人被草拨开
```

---

## 6. 目录结构

```
GrassDemo/
├── Scripts/
│   ├── Grass.cs               # 主驱动：buffer 初始化 / 参数上传 / 间接绘制
│   ├── GrassMesh.cs           # 程序化叶片网格（顶点 + 颜色编码）
│   ├── Clump.cs               # 簇参数结构体
│   └── GrassPresser.cs        # 角色扰动驱动
├── Compute/
│   └── GrassCS.compute        # 草叶生成 + 视锥/距离剔除 + 风 + 扰动
├── Shaders/
│   ├── GrassBlade.shader      # 叶片渲染（贝塞尔展开 + 分簇着色）
│   ├── CubicBezier.hlsl       # 贝塞尔工具函数
│   ├── Voronoi.shader         # 分簇图烘焙
│   └── VoronoiPreview.shader  # 分簇可视化
├── Tools/
│   ├── VoronoiPreviewBoard.cs # 屏幕角落实时预览板
│   └── Editor/
│       └── VoronoiPreviewFix.cs
└── README.md
```

---

## 7. 运行方式

1. Unity **2022.3 LTS** + **URP**
2. 打开场景 `GrassTerrain.unity`
3. 场景里需要：
   - 一个带 `Grass` 组件的物体（填好 ComputeShader / Material / Camera）
   - 一个 `Terrain`
   - 玩家（`SnowCapsuleController` 或任意带移动脚本的物体）
4. Play 后：
   - `WASD` 移动，`Shift` 加速
   - 演示模式见 [第 5 节](#5-演示模式)

---

## 8. 已知限制

| 限制 | 说明 |
|---|---|
| **依赖 Terrain** | 贴地用的是 `Terrain.SampleHeight`，换成非地形地面需要改 `SnapToTerrain` 逻辑 |
| **大世界坐标精度** | 场景坐标在 1000~1500 米量级，float 精度已经开始吃紧（草叶抖动）|
| **单层 LOD** | 目前只有一套叶片精度，远景靠距离剔除减密度，没有真正的 LOD 分级 |
| **波纹槽位固定 32** | 快速拖动时最早的一圈会被覆盖 |
| **体积云无阴影** | 云本身不投影到地面 |

---



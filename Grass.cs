using System.Collections.Generic;
using UnityEngine;

namespace GrassSystem
{
    [DefaultExecutionOrder(200)]
    public class Grass : MonoBehaviour
    {
        [SerializeField]
        private ComputeShader grassCompute;
        [SerializeField]
        private Material bladeMaterial;
        public Camera targetCamera;

        public float bladeSpacing = 0.1f;   // 草叶间距，越小越密，也越吃性能
        public int gridResolution = 100;   // 网格边长，总草叶数是它的平方

        [SerializeField, Range(0, 2)]
        public float positionJitter;   // 整片草的位置抖动，0 = 完全规整的格子

        [Header("随机浮动（哈希伪随机，对称上下浮动，0 = 关闭）")]
        public float heightVariance = 0.15f;   // 高度浮动，太大会像杂草

        public float widthVariance = 0.008f;

        [Header("颜色（Voronoi 簇）")]
        [Range(0f, 1f)]
        public float colorVariance = 0.25f;

        [Range(1, 100)]
        public int clumpTotal = 32;   // 分簇数量，越多簇越碎

        [Header("经过扰动（由 GrassPresser 驱动）")]
        public Vector3 interactorPosition;
        public float interactionRadius = 1.8f;   // 角色影响半径
        public float bendStrength = 0.6f;   // 只影响弯曲和倾斜，不改高度
        public float bendSpeed = 9f;

        public Terrain terrainSource;

        [Header("Culling")]
        public float fadeStartDistance;   // 超过这个距离开始变稀
        public float fadeEndDistance;   // 到这个距离就完全没有了
        [Range(0f, 1f)]
        public float fadeMinDensity;
        public float nearPlaneBias;
        public float screenEdgeBias;

        [Header("Clumping")]
        public int clumpMapHeight;
        public int clumpMapWidth;
        public Material voronoiBakeMaterial;
        public float clumpWorldScale;
        public List<ClumpParameters> clumpGroups;

        [Header("Wind")]
        [SerializeField] private Texture2D windNoiseTex;
        [Range(0.0f, 1.0f)]
        [SerializeField] private float windStrength = 0.5f;
        [SerializeField] private float windScale = 0.01f;
        [SerializeField] private float windSpeed = 0.1f;
        [Range(0.0f, 1.0f)]
        [SerializeField] private float windRotate = 0.3f;

        private static readonly int
            grassBladesBufferID = Shader.PropertyToID("_GrassBlades"),
            resolutionID = Shader.PropertyToID("_Resolution"),
            grassSpacingID = Shader.PropertyToID("_GrassSpacing"),
            grassOriginID = Shader.PropertyToID("_GrassOrigin"),
            jitterStrengthID = Shader.PropertyToID("_JitterStrength"),
            heightJitterID = Shader.PropertyToID("_HeightJitter"),
            widthJitterID = Shader.PropertyToID("_WidthJitter"),
            colorJitterID = Shader.PropertyToID("_ColorJitter"),
            presserPosID = Shader.PropertyToID("_PresserPos"),
            pressRadiusID = Shader.PropertyToID("_PressRadius"),
            disturbStrengthID = Shader.PropertyToID("_DisturbStrength"),
            disturbSpeedID = Shader.PropertyToID("_DisturbSpeed"),
            heightMapID = Shader.PropertyToID("_HeightMap"),
            detailMapID = Shader.PropertyToID("_DetailMap"),
            terrainPositionID = Shader.PropertyToID("_TerrainPosition"),
            heightMapScaleID = Shader.PropertyToID("_HeightMapScale"),
            heightMapMultiplierID = Shader.PropertyToID("_HeightMapMultiplier"),
            distanceCullStartDistID = Shader.PropertyToID("_DistanceCullStartDist"),
            distanceCullEndDistID = Shader.PropertyToID("_DistanceCullEndDist"),
            distanceCullMinimumGrassAmountlID = Shader.PropertyToID("_DistanceCullMinimumGrassAmount"),
            worldSpaceCameraPositionID = Shader.PropertyToID("_WSpaceCameraPos"),
            vpMatrixID = Shader.PropertyToID("_VP_MATRIX"),
            frustumCullNearOffsetID = Shader.PropertyToID("_FrustumCullNearOffset"),
            frustumCullEdgeOffsetID = Shader.PropertyToID("_FrustumCullEdgeOffset"),
            clumpParametersID = Shader.PropertyToID("_ClumpParameters"),
            numClumpParametersID = Shader.PropertyToID("_NumClumpParameters"),
            clumpTexID = Shader.PropertyToID("ClumpTex"),
            clumpScaleID = Shader.PropertyToID("_ClumpScale"),
            LocalWindTexID = Shader.PropertyToID("_LocalWindTex"),
            LocalWindScaleID = Shader.PropertyToID("_LocalWindScale"),
            LocalWindSpeedID = Shader.PropertyToID("_LocalWindSpeed"),
            LocalWindStrengthID = Shader.PropertyToID("_LocalWindStrength"),
            LocalWindRotateAmountID = Shader.PropertyToID("_LocalWindRotateAmount"),
            TimeID = Shader.PropertyToID("_Time");

        private ComputeBuffer bladesBuffer;
        private ComputeBuffer trianglesBuffer;
        private ComputeBuffer colorsBuffer;
        private ComputeBuffer uvsBuffer;
        private ComputeBuffer drawArgsBuffer;
        private ComputeBuffer clumpBuffer;
        private const int ARGS_BUFFER_STRIDE = sizeof(int) * 5;   // IndirectArguments 固定 5 个 int
        private Mesh bladeMesh;
        private Bounds drawBounds;
        private ClumpParameters[] clumpArray;
        private Texture2D clumpMap;

        // 启动时把 buffer 和叶片网格准备好；包围盒给个大值，剔除交给 compute 自己做
        void Awake()
        {
            InitResources();

            drawBounds = new Bounds(Vector3.zero, Vector3.one * 10000f);
        }

        // 放 LateUpdate：必须等相机跟随移动完，否则剔除用的是上一帧的相机位置
        void LateUpdate()
        {
            PushFrameParameters();
            DrawBlades();
        }

        // GPU 资源不手动释放会一直占显存
        void OnDestroy()
        {
            ReleaseBuffers();
            ReleaseClumpMap();
        }

        // 资源初始化：GPU buffer → 叶片网格 → 分簇贴图
        private void InitResources()
        {
            CreateBuffers();
            UploadBladeMesh();
            BakeClumpMap();
        }

        // 草叶用 Append buffer：compute 写完后 Counter 直接当 indirect draw 的实例数
        private void CreateBuffers()
        {
            bladesBuffer = new ComputeBuffer(gridResolution * gridResolution, sizeof(float) * 15, ComputeBufferType.Append);
            bladesBuffer.SetCounterValue(0);

            drawArgsBuffer = new ComputeBuffer(1, ARGS_BUFFER_STRIDE, ComputeBufferType.IndirectArguments);

            clumpBuffer = new ComputeBuffer(clumpGroups.Count, sizeof(float) * 10);
            UploadClumpGroups();
        }

        // 一次性上传只读数据用的小工具
        private ComputeBuffer MakeBuffer<T>(T[] items, int strideBytes) where T : struct
        {
            ComputeBuffer buf = new ComputeBuffer(items.Length, strideBytes);
            buf.SetData(items);
            return buf;
        }

        // 叶片网格只在启动时传一次，后面不再改
        private void UploadBladeMesh()
        {
            bladeMesh = GrassMesh.BuildBladeMesh();
            bladeMesh.name = "Grass Instance Mesh";

            BindBladeMeshData();

            drawArgsBuffer.SetData(new int[] { trianglesBuffer.count, 0, 0, 0, 0 });
        }


        // 三角形 / 颜色 / UV 走 buffer 传给 shader，不走顶点缓冲
        private void BindBladeMeshData()
        {
            int[] tris = bladeMesh.tris;
            Color[] cols = bladeMesh.cols;
            Vector2[] uvCoords = bladeMesh.uv;

            trianglesBuffer = MakeBuffer<int>(tris, sizeof(int));
            colorsBuffer = MakeBuffer<Color>(cols, sizeof(float) * 4);
            uvsBuffer = MakeBuffer<Vector2>(uvCoords, sizeof(float) * 2);

            bladeMaterial.SetBuffer("Triangles", trianglesBuffer);
            bladeMaterial.SetBuffer("Colors", colorsBuffer);
            bladeMaterial.SetBuffer("Uvs", uvsBuffer);
            bladeMaterial.SetBuffer(grassBladesBufferID, bladesBuffer);
        }

        // 用 Voronoi 材质烘焙一张分簇图，compute 采样它决定草叶朝向和颜色
        private void BakeClumpMap()
        {
            voronoiBakeMaterial.SetFloat("_NumClumpTypes", clumpGroups.Count);
            voronoiBakeMaterial.SetFloat("_NumClumps", Mathf.Clamp(clumpTotal, 1, 100));
            RenderTexture clumpRT = RenderTexture.GetTemporary(clumpMapWidth, clumpMapHeight, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            Graphics.Blit(null, clumpRT, voronoiBakeMaterial, 0);

            RenderTexture.active = clumpRT;
            clumpMap = new Texture2D(clumpMapWidth, clumpMapHeight, TextureFormat.RGBAHalf, false, true);
            clumpMap.filterMode = FilterMode.Point;
            clumpMap.ReadPixels(new Rect(0, 0, clumpMapWidth, clumpMapHeight), 0, 0, true);
            clumpMap.Apply();
            RenderTexture.active = null;

            RenderTexture.ReleaseTemporary(clumpRT);
        }

        // 每帧刷新 compute 参数并 dispatch，草叶全部在 GPU 上重新生成
        private void PushFrameParameters()
        {
            bladesBuffer.SetCounterValue(0);

            BindComputeUniforms();

            int groupsX = Mathf.CeilToInt(gridResolution / 8f);
            int groupsZ = Mathf.CeilToInt(gridResolution / 8f);

            grassCompute.Dispatch(0, groupsX, groupsZ, 1);
        }

        // 簇参数只在数量变了才重新上传
        private void UploadClumpGroups()
        {
            if (clumpGroups.Count > 0)
            {
                if (clumpArray == null || clumpArray.Length != clumpGroups.Count)
                {
                    clumpArray = new ClumpParameters[clumpGroups.Count];
                }
                clumpGroups.CopyTo(clumpArray);
                clumpBuffer.SetData(clumpArray);
            }
        }

        // 参数最多的一个方法：基础 → 地形 → 剔除 → 相机 → 扰动 → 分簇 → 风
        private void BindComputeUniforms()
        {
            grassCompute.SetInt(resolutionID, gridResolution);
            grassCompute.SetBuffer(0, grassBladesBufferID, bladesBuffer);
            grassCompute.SetFloat(grassSpacingID, bladeSpacing);
            grassCompute.SetFloat(jitterStrengthID, positionJitter);
            grassCompute.SetFloat(heightJitterID, heightVariance);
            grassCompute.SetFloat(widthJitterID, widthVariance);
            grassCompute.SetFloat(colorJitterID, colorVariance);

            if (terrainSource != null)
            {
                grassCompute.SetVector(terrainPositionID, terrainSource.transform.position);
                grassCompute.SetTexture(0, heightMapID, terrainSource.terrainData.heightmapTexture);
                if (terrainSource.terrainData.alphamapTextures.Length > 0)
                {
                    grassCompute.SetTexture(0, detailMapID, terrainSource.terrainData.alphamapTextures[0]);
                }

                grassCompute.SetFloat(heightMapScaleID, terrainSource.terrainData.size.x);
                grassCompute.SetFloat(heightMapMultiplierID, terrainSource.terrainData.size.y);
            }

            grassCompute.SetFloat(distanceCullStartDistID, fadeStartDistance);
            grassCompute.SetFloat(distanceCullEndDistID, fadeEndDistance);
            grassCompute.SetFloat(distanceCullMinimumGrassAmountlID, fadeMinDensity);
            grassCompute.SetFloat(frustumCullNearOffsetID, nearPlaneBias);
            grassCompute.SetFloat(frustumCullEdgeOffsetID, screenEdgeBias);

            grassCompute.SetVector(worldSpaceCameraPositionID, targetCamera.transform.position);

            float coverSize = gridResolution * bladeSpacing;
            Vector3 cp = targetCamera.transform.position;
            float ox = Mathf.Floor(cp.x / bladeSpacing) * bladeSpacing - coverSize * 0.5f;
            float oz = Mathf.Floor(cp.z / bladeSpacing) * bladeSpacing - coverSize * 0.5f;
            grassCompute.SetVector(grassOriginID, new Vector4(ox, oz, 0f, 0f));

            grassCompute.SetVector(presserPosID, interactorPosition);
            grassCompute.SetFloat(pressRadiusID, Mathf.Max(0.01f, interactionRadius));
            grassCompute.SetFloat(disturbStrengthID, bendStrength);
            grassCompute.SetFloat(disturbSpeedID, bendSpeed);

            Matrix4x4 projMatrix = GL.GetGPUProjectionMatrix(targetCamera.projMatrix, false);
            Matrix4x4 vpMatrix = projMatrix * targetCamera.worldToCameraMatrix;
            grassCompute.SetMatrix(vpMatrixID, vpMatrix);

            UploadClumpGroups();
            grassCompute.SetBuffer(0, clumpParametersID, clumpBuffer);
            grassCompute.SetTexture(0, clumpTexID, clumpMap);
            grassCompute.SetFloat(clumpScaleID, clumpWorldScale);

            grassCompute.SetTexture(0, LocalWindTexID, windNoiseTex);
            grassCompute.SetFloat(LocalWindScaleID, windScale);
            grassCompute.SetFloat(LocalWindSpeedID, windSpeed);
            grassCompute.SetFloat(LocalWindStrengthID, windStrength);
            grassCompute.SetFloat(LocalWindRotateAmountID, windRotate);
            grassCompute.SetFloat(TimeID, Time.time);
        }

        // 从 GPU 取回实例数，DrawProceduralIndirect 一次画完，全程不传网格
        private void DrawBlades()
        {
            ComputeBuffer.CopyCount(bladesBuffer, drawArgsBuffer, sizeof(int));

            Graphics.DrawProceduralIndirect(bladeMaterial, drawBounds, MeshTopology.Triangles, drawArgsBuffer,
                0, null, null, UnityEngine.Rendering.ShadowCastingMode.Off, true, gameObject.layer);
        }


        // 统一释放
        private void ReleaseBuffers()
        {
            ReleaseBuffer(bladesBuffer);
            ReleaseBuffer(trianglesBuffer);
            ReleaseBuffer(colorsBuffer);
            ReleaseBuffer(uvsBuffer);
            ReleaseBuffer(drawArgsBuffer);
            ReleaseBuffer(clumpBuffer);
        }

        // 释放后置空，避免二次 Dispose
        private void ReleaseBuffer(ComputeBuffer buf)
        {
            if (buf != null)
            {
                buf.Dispose();
                buf = null;
            }
        }

        // 烘焙贴图是运行时建的，要手动 Destroy
        private void ReleaseClumpMap()
        {
            if (clumpMap != null)
            {
                Destroy(clumpMap);
                clumpMap = null;
            }
        }

        // 调试用：把 GPU 上的实例数读回 CPU，只看不画
        public int GetVisibleBladeCount()
        {
            if (bladesBuffer == null || drawArgsBuffer == null) return -1;
            ComputeBuffer.CopyCount(bladesBuffer, drawArgsBuffer, 4);
            var arr = new int[5];
            drawArgsBuffer.GetData(arr);
            return arr[1];
        }

    }
}
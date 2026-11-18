using System.Collections.Generic;
using UnityEngine;

// 水面交互波纹。
[DisallowMultipleComponent]
public class WaterRippleEmitter : MonoBehaviour
{
    [Header("水面")]
    public float surfaceHeight = 0f;        // 水面高度，用来判断有没有踩进水里

    public float submergeEpsilon = 0.15f;

    [Header("波源")]
    public Transform[] sources;

    public bool autoBindPlayer = true;

    [Header("发射规则")]
    public float strideEmitPeriod = 0.22f;  // 在水里走的时候，隔多久补一圈

    public float speedThreshold = 0.12f;

    public float entryBoost = 1.6f;

    public float strideBoost = 0.75f;

    public int slotCapacity = 32;           // 必须和 shader 里的数组长度对齐

    [Header("鼠标交互波纹")]
    public bool pointerRipples = true;

    public Camera rayCamera;

    public float pressBoost = 1.4f;

    public float dragStepDistance = 0.55f;  // 拖动多远补一圈

    public float dragMinPeriod = 0.14f;

    public float dragMinBoost = 0.7f;

    public float dragMaxBoost = 1.5f;

    public float dragPeakSpeed = 1400f;     // 鼠标到这个速度就取最大强度

    public float rayMaxDistance = 500f;

    [Header("调试")]
    public bool gizmoDraw = true;           // 选中时画水面高度线和仍存活的波纹

    const int MAX_SLOTS = 32;
    const string RIPPLE_ARRAY_NAME = "_RippleSources";

    readonly Vector4[] _rippleSlots = new Vector4[MAX_SLOTS];
    readonly float[] _sourceTimers = new float[MAX_SLOTS];
    readonly bool[] _wasSubmerged = new bool[MAX_SLOTS];
    readonly Vector3[] _prevPositions = new Vector3[MAX_SLOTS];

    int _writeIndex;
    List<Transform> _sources = new List<Transform>();
    bool _arrayDirty;

    bool _pointerHeld;
    Vector3 _prevHit;
    Vector2 _prevPointer;
    float _prevEmitTime;

    void Awake()
    {
        ResetSlots();
        ResolveSources();
    }

    void OnEnable()
    {
        ResetSlots();
        UploadSlots();
    }

    void OnDisable()
    {
        ResetSlots();
        UploadSlots();
    }

    // 每帧：先处理波源（入水 / 移动），再处理鼠标交互，最后按需推给 shader
    void Update()
    {
        if (_sources.Count == 0) ResolveSources();

        float timestamp = Time.time;
        _arrayDirty = false;

        int activeCount = Mathf.Min(_sources.Count, MAX_SLOTS);

        for (int i = 0; i < activeCount; i++)
        {
            Transform source = _sources[i];
            if (source == null) continue;

            Vector3 worldPos = source.position;
            float deltaTime = Time.deltaTime > 0f ? Time.deltaTime : 0.016f;

            Vector3 motion = worldPos - _prevPositions[i];
            motion.y = 0f;
            float planarSpeed = motion.magnitude / deltaTime;
            _prevPositions[i] = worldPos;

            bool submerged = worldPos.y <= surfaceHeight + submergeEpsilon;
            bool previouslySubmerged = _wasSubmerged[i];
            _wasSubmerged[i] = submerged;

            if (submerged && !previouslySubmerged)
            {
                float fallFactor = Mathf.Clamp(Mathf.Abs(planarSpeed) * 0.15f + 1f, 1f, 2.5f);
                PushRipple(worldPos.x, worldPos.z, timestamp, entryBoost * fallFactor);
                continue;
            }

            if (!submerged) continue;

            if (strideEmitPeriod <= 0f) continue;
            if (planarSpeed < speedThreshold) continue;

            _sourceTimers[i] -= deltaTime;
            if (_sourceTimers[i] > 0f) continue;

            _sourceTimers[i] = strideEmitPeriod;
            PushRipple(worldPos.x, worldPos.z, timestamp, strideBoost * Mathf.Clamp(planarSpeed / 3f, 0.25f, 1.5f));
        }

        UpdatePointerRipples();

        if (_arrayDirty) UploadSlots();
    }

    // 写入一个波纹槽位，槽位用完就环形覆盖最旧的那个
    public void PushRipple(float surfaceX, float surfaceZ, float startTimestamp, float amplitude)
    {
        int slotIndex = _writeIndex;
        _writeIndex = (_writeIndex + 1) % MAX_SLOTS;

        _rippleSlots[slotIndex] = new Vector4(surfaceX, surfaceZ, startTimestamp, Mathf.Max(0.01f, amplitude));
        _arrayDirty = true;
    }

    // 鼠标按下出一圈；按住拖动时按距离和时间双重节流，沿路径连续补圈
    void UpdatePointerRipples()
    {
        if (!pointerRipples) return;

        if (!Input.GetMouseButton(0))
        {
            _pointerHeld = false;
            return;
        }

        Camera viewCamera = rayCamera != null ? rayCamera : Camera.main;
        if (viewCamera == null) return;
        if (!TryRaycastSurface(viewCamera, out Vector3 surfacePoint)) return;

        if (Input.GetMouseButtonDown(0))
        {
            PushRipple(surfacePoint.x, surfacePoint.z, Time.time, pressBoost);
            UploadSlots();

            _pointerHeld = true;
            _prevHit = surfacePoint;
            _prevPointer = Input.mousePosition;
            _prevEmitTime = Time.time;
            return;
        }

        if (!_pointerHeld) return;

        float elapsedSinceEmit = Time.time - _prevEmitTime;
        if (elapsedSinceEmit < dragMinPeriod) return;

        float stepDistance = Vector2.Distance(
            new Vector2(surfacePoint.x, surfacePoint.z),
            new Vector2(_prevHit.x, _prevHit.z));

        if (stepDistance < dragStepDistance) return;

        Vector2 pointerPos = Input.mousePosition;
        float pointerSpeed = (pointerPos - _prevPointer).magnitude / Mathf.Max(elapsedSinceEmit, 1e-4f);
        float speedRatio = Mathf.Clamp01(pointerSpeed / Mathf.Max(1f, dragPeakSpeed));
        float amplitude = Mathf.Lerp(dragMinBoost, dragMaxBoost, speedRatio) * pressBoost;

        int segments = Mathf.Clamp(Mathf.FloorToInt(stepDistance / Mathf.Max(0.01f, dragStepDistance)), 1, 3);
        for (int i = 1; i <= segments; i++)
        {
            Vector3 p = Vector3.Lerp(_prevHit, surfacePoint, i / (float)segments);
            PushRipple(p.x, p.z, Time.time, amplitude);
        }
        UploadSlots();

        _prevHit = surfacePoint;
        _prevPointer = pointerPos;
        _prevEmitTime = Time.time;
    }

    // 屏幕射线和水平面求交，水面不一定有 Collider，所以直接算
    bool TryRaycastSurface(Camera viewCamera, out Vector3 surfacePoint)
    {
        surfacePoint = Vector3.zero;

        Ray viewRay = viewCamera.ScreenPointToRay(Input.mousePosition);

        float directionY = viewRay.direction.y;
        if (Mathf.Abs(directionY) < 1e-5f) return false;

        float travel = (surfaceHeight - viewRay.origin.y) / directionY;
        if (travel <= 0f || travel > rayMaxDistance) return false;

        surfacePoint = viewRay.origin + viewRay.direction * travel;
        return true;
    }

    // 手动触发，比如脚步落地、物体砸进水里的时候调
    public void PushRippleAt(Vector3 worldPos, float amplitude = 1f)
    {
        PushRipple(worldPos.x, worldPos.z, Time.time, amplitude);
        UploadSlots();
    }

    // 清空所有槽位，避免残留的旧波纹卡在水面上
    void ResetSlots()
    {
        for (int i = 0; i < MAX_SLOTS; i++) _rippleSlots[i] = Vector4.zero;
        _writeIndex = 0;
    }

    // 推给 GPU。用全局数组，所有用这个 shader 的材质都能读到
    void UploadSlots()
    {
        Shader.SetGlobalVectorArray(RIPPLE_ARRAY_NAME, _rippleSlots);
    }

    // 收集波源：手动指定的优先，没有就找 Player，再没有就挂主相机上当个兜底
    void ResolveSources()
    {
        _sources.Clear();

        if (sources != null)
        {
            foreach (Transform sourceTransform in sources)
                if (sourceTransform != null) _sources.Add(sourceTransform);
        }

        if (_sources.Count == 0 && autoBindPlayer)
        {
            var player = GameObject.FindWithTag("Player");
            if (player != null) _sources.Add(player.transform);
        }

        if (_sources.Count == 0)
        {
            var viewCamera = Camera.main;
            if (viewCamera != null) _sources.Add(viewCamera.transform);
        }

        if (_sources.Count > _sourceTimers.Length)
            Debug.LogWarning("[WaterRipple] Source count exceeds " + _sourceTimers.Length + ", extra sources ignored.");

        for (int i = 0; i < _sources.Count && i < _prevPositions.Length; i++)
        {
            if (_sources[i] != null) _prevPositions[i] = _sources[i].position;
            _wasSubmerged[i] = _sources[i] != null &&
                             _sources[i].position.y <= surfaceHeight + submergeEpsilon;
        }
    }

    void OnDrawGizmosSelected()
    {
        if (!gizmoDraw) return;

        Gizmos.color = new Color(0.2f, 0.8f, 1f, 0.6f);
        Vector3 center = transform.position;
        Gizmos.DrawLine(new Vector3(center.x - 30f, surfaceHeight, center.z),
                        new Vector3(center.x + 30f, surfaceHeight, center.z));
        Gizmos.DrawLine(new Vector3(center.x, surfaceHeight, center.z - 30f),
                        new Vector3(center.x, surfaceHeight, center.z + 30f));

        if (!Application.isPlaying) return;
        Gizmos.color = new Color(1f, 1f, 0.4f, 0.9f);
        foreach (Vector4 slot in _rippleSlots)
        {
            if (slot.w <= 0f) continue;
            Gizmos.DrawWireSphere(new Vector3(slot.x, surfaceHeight, slot.y), 0.5f);
        }
    }
}

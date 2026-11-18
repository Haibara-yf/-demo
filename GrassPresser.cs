using UnityEngine;
using GrassSystem;

[DefaultExecutionOrder(-50)]
public class GrassPresser : MonoBehaviour
{
    [Header("引用")]
    public Grass grassTarget;

    [Header("扰动参数")]
    public float effectRadius = 1.8f;

    public float swayStrength = 0.6f;

    public float swaySpeed = 9f;

    public bool onlyWhileMoving = false;

    public float motionThreshold = 0.15f;

    private Vector3 previousPosition;
    private bool hasPrevious;

    private void Start()
    {
        // 没指定就自己在场景里找一个
        if (grassTarget == null) grassTarget = FindObjectOfType<Grass>();
        if (grassTarget == null)
        {
            Debug.LogWarning("[扰动] 场景里没有 Grass，GrassPresser 不生效。");
            enabled = false;
            return;
        }

        previousPosition = transform.position;
        hasPrevious = true;
        ApplyToGrass(transform.position, 0f);
    }

    // 每帧把位置和速度丢给 Grass
    private void Update()
    {
        if (grassTarget == null) return;

        Vector3 currentPos = transform.position;
        float stepLength = hasPrevious ? Vector3.Distance(currentPos, previousPosition) : 0f;
        float planarSpeed = Time.deltaTime > 0f ? stepLength / Time.deltaTime : 0f;

        bool isMoving = !onlyWhileMoving || planarSpeed > motionThreshold;
        float swayAmount = isMoving ? swayStrength : 0f;

        ApplyToGrass(currentPos, swayAmount);

        previousPosition = currentPos;
        hasPrevious = true;
    }

    private void ApplyToGrass(Vector3 worldPos, float swayAmount)
    {
        grassTarget.interactorPosition = worldPos;
        grassTarget.interactionRadius = Mathf.Max(0.05f, effectRadius);
        grassTarget.bendStrength = swayAmount;
        grassTarget.bendSpeed = swaySpeed;
    }

    private void OnDisable()
    {
        if (grassTarget != null) grassTarget.bendStrength = 0f;
    }
}

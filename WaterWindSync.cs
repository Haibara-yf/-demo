using System.Reflection;
using UnityEngine;

// 把草地的风场参数同步到水面材质。
// 两边的风向原本各写各的，会各刮各的风，挂上这个之后草和水是同一阵风。
// 参数是从 Grass 组件上用反射读的（没有公开接口），读不到就退回手动值。
[DisallowMultipleComponent]
public class WaterWindSync : MonoBehaviour
{
    [Header("数据源（可选）")]
    public MonoBehaviour grassProvider;     // 带 Grass 组件的物体，留空就用下面的手动值

    [Header("水面")]
    public Material targetMaterial;         // 风场参数写到这个材质上

    [Header("手动参数（无 Grass Source 时生效）")]
    public Texture2D manualWindTex;
    public float manualWindScale = 0.01f;
    public float manualWindSpeed = 0.1f;
    public float manualWindStrength = 0.35f;

    public bool pollEveryFrame = false;     // 勾上=每帧检查一次

    Texture _cachedTex;
    float _cachedScale = float.NaN, _cachedSpeed = float.NaN, _cachedStrength = float.NaN;

    static readonly string[] TexMemberNames = { "localWindTex" };
    static readonly string[] ScaleMemberNames = { "localWindScale" };
    static readonly string[] SpeedMemberNames = { "localWindSpeed" };
    static readonly string[] StrengthMemberNames = { "localWindStrength" };

    void Start() { ApplyToMaterial(true); }

    void OnValidate() { ApplyToMaterial(true); }

    void Update()
    {
        if (pollEveryFrame) ApplyToMaterial(false);
    }

    // 读草地的参数并写进水面材质，值没变就跳过
    void ApplyToMaterial(bool forceApply)
    {
        if (targetMaterial == null) return;

        Texture2D windTexture = null;
        float scaleValue = manualWindScale, speedValue = manualWindSpeed, strengthValue = manualWindStrength;

        if (grassProvider != null)
        {
            windTexture   = ReadMember<Texture2D>(grassProvider, TexMemberNames, windTexture);
            scaleValue    = ReadMember(grassProvider, ScaleMemberNames, scaleValue);
            speedValue    = ReadMember(grassProvider, SpeedMemberNames, speedValue);
            strengthValue = ReadMember(grassProvider, StrengthMemberNames, strengthValue);
        }
        else
        {
            windTexture = manualWindTex;
        }

        if (windTexture == null) return;

        if (!forceApply
            && windTexture == _cachedTex
            && Mathf.Approximately(scaleValue, _cachedScale)
            && Mathf.Approximately(speedValue, _cachedSpeed)
            && Mathf.Approximately(strengthValue, _cachedStrength))
            return;

        targetMaterial.SetTexture("_WindTex", windTexture);
        targetMaterial.SetFloat("_WindScale", scaleValue);
        targetMaterial.SetFloat("_WindSpeed", speedValue);
        targetMaterial.SetFloat("_WindStrength", strengthValue);

        _cachedTex = windTexture;
        _cachedScale = scaleValue;
        _cachedSpeed = speedValue;
        _cachedStrength = strengthValue;
    }

    // 反射读字段或属性，类型不对或者读不到就返回默认值
    static T ReadMember<T>(object target, string[] memberNames, T defaultValue) where T : class
    {
        object rawValue = ReadMemberRaw(target, memberNames);
        return rawValue as T ?? defaultValue;
    }

    static float ReadMember(object target, string[] memberNames, float defaultValue)
    {
        object rawValue = ReadMemberRaw(target, memberNames);
        if (rawValue is float f) return f;
        if (rawValue is double d) return (float)d;
        return defaultValue;
    }

    // 返回第一个能读到的值（字段和属性都试）
    static object ReadMemberRaw(object target, string[] memberNames)
    {
        if (target == null) return null;

        var targetType = target.GetType();
        const BindingFlags memberFlags = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;

        foreach (string memberName in memberNames)
        {
            var fieldInfo = targetType.GetField(memberName, memberFlags);
            if (fieldInfo != null) return fieldInfo.GetValue(target);

            var propInfo = targetType.GetProperty(memberName, memberFlags);
            if (propInfo != null) return propInfo.GetValue(target, null);
        }
        return null;
    }
}

using UnityEngine;

/// <summary>
/// 双 SDF 绑定器。
/// 
/// Object SDF Textures:
///     石头、树根、道具等“物体”的 SDF。
///     地面材质 Fusion Mode = 0 时会采样这组 SDF。
/// 
/// Ground SDF Textures:
///     地面、薄地面块、地形接触面的 SDF。
///     石头材质 Fusion Mode = 1 时会采样这组 SDF。
/// </summary>
[ExecuteAlways]
public class SDFDualGlobalBinder : MonoBehaviour
{
    [Header("Object SDF Textures：石头 / 树根 / 道具")]
    [Tooltip("地面材质 Fusion Mode = 0 时，会采样这组 SDF。")]
    public SDFTexture[] objectSDFTextures = new SDFTexture[4];

    [Header("Ground SDF Textures：地面 / 薄地面块 / Terrain 接触面")]
    [Tooltip("石头材质 Fusion Mode = 1 时，会采样这组 SDF。")]
    public SDFTexture[] groundSDFTextures = new SDFTexture[4];

    static readonly int[] ObjectSDF_ID =
    {
        Shader.PropertyToID("_ObjectSDF0"),
        Shader.PropertyToID("_ObjectSDF1"),
        Shader.PropertyToID("_ObjectSDF2"),
        Shader.PropertyToID("_ObjectSDF3")
    };

    static readonly int[] ObjectSDFWorldToTex_ID =
    {
        Shader.PropertyToID("_ObjectSDF0_WorldToTex"),
        Shader.PropertyToID("_ObjectSDF1_WorldToTex"),
        Shader.PropertyToID("_ObjectSDF2_WorldToTex"),
        Shader.PropertyToID("_ObjectSDF3_WorldToTex")
    };

    static readonly int[] ObjectSDFValid_ID =
    {
        Shader.PropertyToID("_ObjectSDF0_Valid"),
        Shader.PropertyToID("_ObjectSDF1_Valid"),
        Shader.PropertyToID("_ObjectSDF2_Valid"),
        Shader.PropertyToID("_ObjectSDF3_Valid")
    };

    static readonly int[] GroundSDF_ID =
    {
        Shader.PropertyToID("_GroundSDF0"),
        Shader.PropertyToID("_GroundSDF1"),
        Shader.PropertyToID("_GroundSDF2"),
        Shader.PropertyToID("_GroundSDF3")
    };

    static readonly int[] GroundSDFWorldToTex_ID =
    {
        Shader.PropertyToID("_GroundSDF0_WorldToTex"),
        Shader.PropertyToID("_GroundSDF1_WorldToTex"),
        Shader.PropertyToID("_GroundSDF2_WorldToTex"),
        Shader.PropertyToID("_GroundSDF3_WorldToTex")
    };

    static readonly int[] GroundSDFValid_ID =
    {
        Shader.PropertyToID("_GroundSDF0_Valid"),
        Shader.PropertyToID("_GroundSDF1_Valid"),
        Shader.PropertyToID("_GroundSDF2_Valid"),
        Shader.PropertyToID("_GroundSDF3_Valid")
    };

    void OnEnable()
    {
        EnsureArraySizes();
        Apply();
    }

    void OnValidate()
    {
        EnsureArraySizes();
        Apply();
    }

    void LateUpdate()
    {
        Apply();
    }

    void EnsureArraySizes()
    {
        objectSDFTextures = EnsureArraySize(objectSDFTextures);
        groundSDFTextures = EnsureArraySize(groundSDFTextures);
    }

    SDFTexture[] EnsureArraySize(SDFTexture[] source)
    {
        if (source == null)
            return new SDFTexture[4];

        if (source.Length == 4)
            return source;

        SDFTexture[] fixedArray = new SDFTexture[4];

        int copyCount = Mathf.Min(source.Length, fixedArray.Length);
        for (int i = 0; i < copyCount; i++)
        {
            fixedArray[i] = source[i];
        }

        return fixedArray;
    }

    void Apply()
    {
        EnsureArraySizes();

        ApplySDFSet(
            objectSDFTextures,
            ObjectSDF_ID,
            ObjectSDFWorldToTex_ID,
            ObjectSDFValid_ID
        );

        ApplySDFSet(
            groundSDFTextures,
            GroundSDF_ID,
            GroundSDFWorldToTex_ID,
            GroundSDFValid_ID
        );
    }

    void ApplySDFSet(
        SDFTexture[] sdfTextures,
        int[] textureIDs,
        int[] matrixIDs,
        int[] validIDs
    )
    {
        for (int i = 0; i < 4; i++)
        {
            SDFTexture sdfTexture = sdfTextures[i];

            bool isValid =
                sdfTexture != null &&
                sdfTexture.sdf != null;

            Shader.SetGlobalFloat(validIDs[i], isValid ? 1f : 0f);

            if (!isValid)
                continue;

            Shader.SetGlobalTexture(textureIDs[i], sdfTexture.sdf);
            Shader.SetGlobalMatrix(matrixIDs[i], sdfTexture.worldToSDFTexCoords);
        }
    }
}
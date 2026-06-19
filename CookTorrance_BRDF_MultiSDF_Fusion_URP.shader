Shader "Custom/CookTorrance BRDF SDF Fusion URP"
{
    Properties
    {
        [Header(Base BRDF Material)]
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalScale("Normal Scale", Range(0, 2)) = 1

        _Metallic("Metallic", Range(0, 1)) = 0
        _MetallicMap("Metallic Map", 2D) = "white" {}

        _Roughness("Roughness", Range(0.02, 1)) = 0.5
        _RoughnessMap("Roughness Map", 2D) = "white" {}

        _OcclusionStrength("Occlusion Strength", Range(0, 1)) = 1
        _OcclusionMap("Occlusion Map", 2D) = "white" {}

        _DiffuseStrength("Diffuse Strength", Range(0, 2)) = 1
        _SpecularStrength("Specular Strength", Range(0, 5)) = 1

        _IndirectDiffuseStrength("Indirect Diffuse Strength", Range(0, 2)) = 1
        _EnvironmentReflectionStrength("Environment Reflection Strength", Range(0, 2)) = 1

        [Header(Fusion Mode)]
        _FusionMode("Fusion Mode 0 Ground Receives Object SDF 1 Object Receives Ground SDF", Range(0, 1)) = 0

        [Header(Fusion Color)]
        _FusionMap("Fusion Map", 2D) = "white" {}
        _FusionColor("Fusion Tint", Color) = (0.62, 0.82, 0.34, 1)
        _FusionWorldTiling("Fusion World Tiling", Float) = 0.7

        [Header(Fusion Normal)]
        [Normal] _FusionNormalMap("Fusion Normal Map", 2D) = "bump" {}
        _FusionNormalScale("Fusion Normal Scale", Range(0, 2)) = 1
        _FusionNormalBlendStrength("Fusion Normal Blend Strength", Range(0, 1)) = 0
        _FusionNormalBlendPower("Fusion Normal Blend Power", Range(0.2, 4)) = 1
        _FusionNormalWorldTiling("Fusion Normal World Tiling", Float) = 0.7
        _FusionNormalUseWorldUV("Fusion Normal Use World UV 0 BaseUV 1 WorldXZ", Range(0, 1)) = 1

        [Header(SDF Fusion)]
        _SDFBlendWidth("SDF Blend Width", Range(0, 1)) = 0.04
        _SDFBlendStrength("SDF Blend Strength", Range(0, 1)) = 1
        _SDFSurfaceOffset("SDF Surface Offset", Range(-0.1, 0.1)) = 0
        _SDFEdgeNoiseStrength("SDF Edge Noise Strength", Range(0, 1)) = 0.35
        _SDFEdgeNoiseScale("SDF Edge Noise Scale", Float) = 6
        _SDFVolumeEdgeFade("SDF Volume Edge Fade", Range(0.001, 0.25)) = 0.04
        _SDFDistanceDebugScale("SDF Distance Debug Scale", Float) = 12

        [Header(Fusion BRDF Override)]
        _FusionDarken("Fusion Darken", Range(0, 1)) = 0.25
        _FusionRoughness("Fusion Roughness", Range(0.02, 1)) = 0.85
        _FusionOcclusion("Fusion Occlusion", Range(0, 1)) = 0.75

        [Header(Safe Lighting)]
        _MinimumAmbient("Minimum Ambient", Range(0, 1)) = 0.12

        [Header(Debug)]
        _DebugMode("Debug Mode 0 Final 1 Mask 2 Raw SDF 3 Normal Mask", Range(0, 3)) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Cull Back
            ZWrite On
            ZTest LEqual
            Blend Off

            HLSLPROGRAM

            #pragma target 3.0

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            #pragma multi_compile_fragment _ _ENVIRONMENTREFLECTIONS_OFF

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                float2 staticLightmapUV : TEXCOORD1;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;

                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;

                float2 uv : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;

                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 6);
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            TEXTURE2D(_MetallicMap);
            SAMPLER(sampler_MetallicMap);

            TEXTURE2D(_RoughnessMap);
            SAMPLER(sampler_RoughnessMap);

            TEXTURE2D(_OcclusionMap);
            SAMPLER(sampler_OcclusionMap);

            TEXTURE2D(_FusionMap);
            SAMPLER(sampler_FusionMap);

            TEXTURE2D(_FusionNormalMap);
            SAMPLER(sampler_FusionNormalMap);

            // 关键修改：
            // 只给 _ObjectSDF0 保留一个 sampler，后面所有 SDF 体积贴图都共用 sampler_ObjectSDF0。
            // 这样可以避免 ps_4_0 sampler register 超过 16 个。
            TEXTURE3D(_ObjectSDF0);
            SAMPLER(sampler_ObjectSDF0);

            TEXTURE3D(_ObjectSDF1);
            TEXTURE3D(_ObjectSDF2);
            TEXTURE3D(_ObjectSDF3);

            TEXTURE3D(_GroundSDF0);
            TEXTURE3D(_GroundSDF1);
            TEXTURE3D(_GroundSDF2);
            TEXTURE3D(_GroundSDF3);

            float4x4 _ObjectSDF0_WorldToTex;
            float4x4 _ObjectSDF1_WorldToTex;
            float4x4 _ObjectSDF2_WorldToTex;
            float4x4 _ObjectSDF3_WorldToTex;

            float4x4 _GroundSDF0_WorldToTex;
            float4x4 _GroundSDF1_WorldToTex;
            float4x4 _GroundSDF2_WorldToTex;
            float4x4 _GroundSDF3_WorldToTex;

            float _ObjectSDF0_Valid;
            float _ObjectSDF1_Valid;
            float _ObjectSDF2_Valid;
            float _ObjectSDF3_Valid;

            float _GroundSDF0_Valid;
            float _GroundSDF1_Valid;
            float _GroundSDF2_Valid;
            float _GroundSDF3_Valid;

            CBUFFER_START(UnityPerMaterial)

                float4 _BaseColor;
                float4 _BaseMap_ST;

                float4 _NormalMap_ST;
                float4 _MetallicMap_ST;
                float4 _RoughnessMap_ST;
                float4 _OcclusionMap_ST;

                float _NormalScale;

                float _Metallic;
                float _Roughness;

                float _OcclusionStrength;

                float _DiffuseStrength;
                float _SpecularStrength;

                float _IndirectDiffuseStrength;
                float _EnvironmentReflectionStrength;

                float _FusionMode;

                float4 _FusionMap_ST;
                float4 _FusionColor;
                float _FusionWorldTiling;

                float4 _FusionNormalMap_ST;
                float _FusionNormalScale;
                float _FusionNormalBlendStrength;
                float _FusionNormalBlendPower;
                float _FusionNormalWorldTiling;
                float _FusionNormalUseWorldUV;

                float _SDFBlendWidth;
                float _SDFBlendStrength;
                float _SDFSurfaceOffset;
                float _SDFEdgeNoiseStrength;
                float _SDFEdgeNoiseScale;
                float _SDFVolumeEdgeFade;
                float _SDFDistanceDebugScale;

                float _FusionDarken;
                float _FusionRoughness;
                float _FusionOcclusion;

                float _MinimumAmbient;

                float _DebugMode;

            CBUFFER_END

            #define BRDF_EPSILON 0.00001
            #define BRDF_INV_PI 0.31830988618

            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);

                float a = Hash21(i);
                float b = Hash21(i + float2(1, 0));
                float c = Hash21(i + float2(0, 1));
                float d = Hash21(i + float2(1, 1));

                float2 u = f * f * (3.0 - 2.0 * f);

                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }

            float3 GetF0(float3 albedo, float metallic)
            {
                float3 dielectricF0 = float3(0.04, 0.04, 0.04);
                return lerp(dielectricF0, albedo, metallic);
            }

            float DistributionGGX_DGF(float NdotH, float roughness)
            {
                roughness = max(roughness, 0.02);

                float alpha = roughness * roughness;
                float alpha2 = alpha * alpha;

                float NdotH2 = NdotH * NdotH;

                float denom = NdotH2 * (alpha2 - 1.0) + 1.0;
                denom = PI * denom * denom;

                return alpha2 / max(denom, BRDF_EPSILON);
            }

            float GeometrySmithHeightCorrelatedGGX_DGF(float NdotV, float NdotL, float roughness)
            {
                roughness = max(roughness, 0.02);

                float alpha = roughness * roughness;
                float alpha2 = alpha * alpha;

                float lambdaV =
                    NdotL * sqrt(NdotV * (NdotV - NdotV * alpha2) + alpha2);

                float lambdaL =
                    NdotV * sqrt(NdotL * (NdotL - NdotL * alpha2) + alpha2);

                float G =
                    2.0 * NdotL * NdotV / max(lambdaV + lambdaL, BRDF_EPSILON);

                return saturate(G);
            }

            float3 FresnelSchlickF90_DGF(float VdotH, float3 F0)
            {
                VdotH = saturate(VdotH);

                float3 F90 = float3(1.0, 1.0, 1.0);
                float fresnel = pow(1.0 - VdotH, 5.0);

                return F0 + (F90 - F0) * fresnel;
            }

            float3 FresnelSchlickRoughness_DGF(float cosTheta, float3 F0, float roughness)
            {
                cosTheta = saturate(cosTheta);

                float3 roughnessF90 =
                    max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0);

                return F0 + (roughnessF90 - F0) * pow(1.0 - cosTheta, 5.0);
            }

            float GetSDFVolumeEdgeFade(float3 uvw)
            {
                float3 edgeDistance = min(uvw, 1.0 - uvw);
                float nearestEdge = min(edgeDistance.x, min(edgeDistance.y, edgeDistance.z));

                return smoothstep(0.0, max(_SDFVolumeEdgeFade, 0.0001), nearestEdge);
            }

            float ComputeMaskFromRawSDF(float3 positionWS, float rawSDF, float3 uvw, float insideVolume)
            {
                if (insideVolume < 0.5)
                {
                    return 0.0;
                }

                float d =
                    abs(rawSDF - _SDFSurfaceOffset);

                float width =
                    max(_SDFBlendWidth, 0.0001);

                float noise =
                    ValueNoise(positionWS.xz * _SDFEdgeNoiseScale);

                noise =
                    (noise - 0.5) * _SDFEdgeNoiseStrength * width;

                float mask =
                    1.0 - smoothstep(0.0, width, d + noise);

                float volumeEdgeFade =
                    GetSDFVolumeEdgeFade(uvw);

                return saturate(mask * volumeEdgeFade * _SDFBlendStrength);
            }

            float SampleObjectSDF0(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_ObjectSDF0_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_ObjectSDF0, sampler_ObjectSDF0, uvw).r;
            }

            float SampleObjectSDF1(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_ObjectSDF1_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_ObjectSDF1, sampler_ObjectSDF0, uvw).r;
            }

            float SampleObjectSDF2(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_ObjectSDF2_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_ObjectSDF2, sampler_ObjectSDF0, uvw).r;
            }

            float SampleObjectSDF3(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_ObjectSDF3_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_ObjectSDF3, sampler_ObjectSDF0, uvw).r;
            }

            float SampleGroundSDF0(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_GroundSDF0_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_GroundSDF0, sampler_ObjectSDF0, uvw).r;
            }

            float SampleGroundSDF1(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_GroundSDF1_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_GroundSDF1, sampler_ObjectSDF0, uvw).r;
            }

            float SampleGroundSDF2(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_GroundSDF2_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_GroundSDF2, sampler_ObjectSDF0, uvw).r;
            }

            float SampleGroundSDF3(float3 positionWS, out float3 uvw, out float insideVolume)
            {
                uvw = mul(_GroundSDF3_WorldToTex, float4(positionWS, 1.0)).xyz;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                {
                    insideVolume = 0.0;
                    return 999.0;
                }

                insideVolume = 1.0;
                return SAMPLE_TEXTURE3D(_GroundSDF3, sampler_ObjectSDF0, uvw).r;
            }

            float GetObjectSDFMask(float3 positionWS)
            {
                float mask = 0.0;

                if (_ObjectSDF0_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleObjectSDF0(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                if (_ObjectSDF1_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleObjectSDF1(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                if (_ObjectSDF2_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleObjectSDF2(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                if (_ObjectSDF3_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleObjectSDF3(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                return saturate(mask);
            }

            float GetGroundSDFMask(float3 positionWS)
            {
                float mask = 0.0;

                if (_GroundSDF0_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleGroundSDF0(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                if (_GroundSDF1_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleGroundSDF1(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                if (_GroundSDF2_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleGroundSDF2(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                if (_GroundSDF3_Valid > 0.5)
                {
                    float3 uvw;
                    float insideVolume;
                    float rawSDF = SampleGroundSDF3(positionWS, uvw, insideVolume);
                    mask = max(mask, ComputeMaskFromRawSDF(positionWS, rawSDF, uvw, insideVolume));
                }

                return saturate(mask);
            }

            float GetRawSDFDebugValue(float3 positionWS)
            {
                float minD = 999.0;

                if (_FusionMode < 0.5)
                {
                    if (_ObjectSDF0_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleObjectSDF0(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }

                    if (_ObjectSDF1_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleObjectSDF1(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }

                    if (_ObjectSDF2_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleObjectSDF2(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }

                    if (_ObjectSDF3_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleObjectSDF3(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }
                }
                else
                {
                    if (_GroundSDF0_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleGroundSDF0(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }

                    if (_GroundSDF1_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleGroundSDF1(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }

                    if (_GroundSDF2_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleGroundSDF2(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }

                    if (_GroundSDF3_Valid > 0.5)
                    {
                        float3 uvw;
                        float insideVolume;
                        float rawSDF = SampleGroundSDF3(positionWS, uvw, insideVolume);
                        if (insideVolume > 0.5)
                            minD = min(minD, abs(rawSDF - _SDFSurfaceOffset));
                    }
                }

                if (minD > 998.0)
                    return 0.0;

                return saturate(minD * _SDFDistanceDebugScale);
            }

            float GetFusionMask(float3 positionWS)
            {
                if (_FusionMode < 0.5)
                {
                    return GetObjectSDFMask(positionWS);
                }

                return GetGroundSDFMask(positionWS);
            }

            float GetFusionNormalMask(float fusionMask)
            {
                float normalMask =
                    saturate(fusionMask * _FusionNormalBlendStrength);

                normalMask =
                    pow(normalMask, max(_FusionNormalBlendPower, 0.0001));

                return saturate(normalMask);
            }

            float3 EvaluateDirectLight_DGF(
                float3 albedo,
                float metallic,
                float roughness,
                float3 N,
                float3 V,
                float3 L,
                float3 lightColor,
                float attenuation
            )
            {
                float3 H = normalize(L + V);

                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));
                float NdotH = saturate(dot(N, H));
                float VdotH = saturate(dot(V, H));

                if (NdotL <= 0.0 || NdotV <= 0.0)
                {
                    return float3(0.0, 0.0, 0.0);
                }

                float3 F0 = GetF0(albedo, metallic);

                float D =
                    DistributionGGX_DGF(NdotH, roughness);

                float G =
                    GeometrySmithHeightCorrelatedGGX_DGF(NdotV, NdotL, roughness);

                float3 F =
                    FresnelSchlickF90_DGF(VdotH, F0);

                float denominator =
                    4.0 * NdotV * NdotL + BRDF_EPSILON;

                float3 specularBRDF =
                    (D * G * F) / denominator;

                specularBRDF *= _SpecularStrength;

                float3 diffuseBRDF =
                    albedo * BRDF_INV_PI;

                float3 kS = F;
                float3 kD = 1.0 - kS;
                kD *= 1.0 - metallic;

                float3 result =
                    (kD * diffuseBRDF * _DiffuseStrength + specularBRDF)
                    * lightColor
                    * NdotL
                    * attenuation;

                return result;
            }

            float3 EvaluateIndirectLight_DGF(
                float3 albedo,
                float metallic,
                float roughness,
                float ao,
                float3 N,
                float3 V,
                float3 bakedGI
            )
            {
                float NdotV =
                    saturate(dot(N, V));

                float3 F0 =
                    GetF0(albedo, metallic);

                float3 F =
                    FresnelSchlickRoughness_DGF(NdotV, F0, roughness);

                float3 kS = F;
                float3 kD = 1.0 - kS;
                kD *= 1.0 - metallic;

                float3 safeGI =
                    max(bakedGI, float3(_MinimumAmbient, _MinimumAmbient, _MinimumAmbient));

                float3 indirectDiffuse =
                    safeGI
                    * albedo
                    * kD
                    * ao
                    * _IndirectDiffuseStrength;

                float3 R =
                    reflect(-V, N);

                float3 indirectSpecularEnv =
                    GlossyEnvironmentReflection(R, roughness, ao);

                float3 indirectSpecular =
                    indirectSpecularEnv
                    * F
                    * _SpecularStrength
                    * _EnvironmentReflectionStrength;

                return indirectDiffuse + indirectSpecular;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(input.positionOS.xyz);

                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionHCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;

                output.normalWS = normalInputs.normalWS;
                output.tangentWS = normalInputs.tangentWS;
                output.bitangentWS = normalInputs.bitangentWS;

                output.uv = input.uv;

                output.shadowCoord =
                    TransformWorldToShadowCoord(output.positionWS);

                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.lightmapUV);
                OUTPUT_SH(output.normalWS, output.vertexSH);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float2 baseUV =
                    TRANSFORM_TEX(input.uv, _BaseMap);

                float2 normalUV =
                    TRANSFORM_TEX(input.uv, _NormalMap);

                float2 metallicUV =
                    TRANSFORM_TEX(input.uv, _MetallicMap);

                float2 roughnessUV =
                    TRANSFORM_TEX(input.uv, _RoughnessMap);

                float2 occlusionUV =
                    TRANSFORM_TEX(input.uv, _OcclusionMap);

                float4 baseSample =
                    SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, baseUV);

                float3 albedo =
                    baseSample.rgb * _BaseColor.rgb;

                float fusionMask =
                    GetFusionMask(input.positionWS);

                float fusionNormalMask =
                    GetFusionNormalMask(fusionMask);

                if (_DebugMode > 0.5 && _DebugMode < 1.5)
                {
                    return half4(fusionMask.xxx, 1.0);
                }

                if (_DebugMode >= 1.5 && _DebugMode < 2.5)
                {
                    float debugValue =
                        GetRawSDFDebugValue(input.positionWS);

                    return half4(debugValue.xxx, 1.0);
                }

                if (_DebugMode >= 2.5)
                {
                    return half4(fusionNormalMask.xxx, 1.0);
                }

                float2 fusionUV =
                    input.positionWS.xz * _FusionWorldTiling;

                float3 fusionColor =
                    SAMPLE_TEXTURE2D(_FusionMap, sampler_FusionMap, fusionUV).rgb
                    * _FusionColor.rgb;

                albedo =
                    lerp(albedo, fusionColor, fusionMask);

                albedo *=
                    lerp(1.0, 1.0 - _FusionDarken, fusionMask);

                float4 normalSample =
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, normalUV);

                float3 baseNormalTS =
                    UnpackNormalScale(normalSample, _NormalScale);

                float2 fusionNormalBaseUV =
                    TRANSFORM_TEX(input.uv, _FusionNormalMap);

                float2 fusionNormalWorldUV =
                    input.positionWS.xz * _FusionNormalWorldTiling;

                float useWorldUV =
                    step(0.5, _FusionNormalUseWorldUV);

                float2 fusionNormalUV =
                    lerp(fusionNormalBaseUV, fusionNormalWorldUV, useWorldUV);

                float4 fusionNormalSample =
                    SAMPLE_TEXTURE2D(_FusionNormalMap, sampler_FusionNormalMap, fusionNormalUV);

                float3 fusionNormalTS =
                    UnpackNormalScale(fusionNormalSample, _FusionNormalScale);

                float3 finalNormalTS =
                    normalize(lerp(baseNormalTS, fusionNormalTS, fusionNormalMask));

                float3x3 tangentToWorld =
                    float3x3(
                        normalize(input.tangentWS),
                        normalize(input.bitangentWS),
                        normalize(input.normalWS)
                    );

                float3 N =
                    normalize(TransformTangentToWorld(finalNormalTS, tangentToWorld));

                float metallicTex =
                    SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, metallicUV).r;

                float metallic =
                    saturate(metallicTex * _Metallic);

                float roughnessTex =
                    SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, roughnessUV).r;

                float roughness =
                    saturate(roughnessTex * _Roughness);

                roughness =
                    lerp(roughness, _FusionRoughness, fusionMask);

                roughness =
                    max(roughness, 0.02);

                float aoTex =
                    SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, occlusionUV).r;

                float ao =
                    lerp(1.0, aoTex, _OcclusionStrength);

                ao =
                    lerp(ao, _FusionOcclusion, fusionMask);

                float3 V =
                    normalize(GetWorldSpaceViewDir(input.positionWS));

                half3 bakedGI =
                    SAMPLE_GI(input.lightmapUV, input.vertexSH, N);

                Light mainLight =
                    GetMainLight(input.shadowCoord);

                float3 L =
                    normalize(mainLight.direction);

                float mainAttenuation =
                    mainLight.distanceAttenuation *
                    mainLight.shadowAttenuation;

                float3 finalColor =
                    EvaluateDirectLight_DGF(
                        albedo,
                        metallic,
                        roughness,
                        N,
                        V,
                        L,
                        mainLight.color,
                        mainAttenuation
                    );

                #ifdef _ADDITIONAL_LIGHTS

                    uint additionalLightCount =
                        GetAdditionalLightsCount();

                    for (uint lightIndex = 0u; lightIndex < additionalLightCount; lightIndex++)
                    {
                        Light addLight =
                            GetAdditionalLight(lightIndex, input.positionWS);

                        float3 addL =
                            normalize(addLight.direction);

                        float addAttenuation =
                            addLight.distanceAttenuation *
                            addLight.shadowAttenuation;

                        finalColor +=
                            EvaluateDirectLight_DGF(
                                albedo,
                                metallic,
                                roughness,
                                N,
                                V,
                                addL,
                                addLight.color,
                                addAttenuation
                            );
                    }

                #endif

                finalColor +=
                    EvaluateIndirectLight_DGF(
                        albedo,
                        metallic,
                        roughness,
                        ao,
                        N,
                        V,
                        bakedGI
                    );

                return half4(finalColor, 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"

            Tags
            {
                "LightMode" = "DepthOnly"
            }

            Cull Back
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM

            #pragma target 3.0
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct DepthOnlyAttributes
            {
                float4 positionOS : POSITION;
            };

            struct DepthOnlyVaryings
            {
                float4 positionHCS : SV_POSITION;
            };

            DepthOnlyVaryings DepthOnlyVertex(DepthOnlyAttributes input)
            {
                DepthOnlyVaryings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 DepthOnlyFragment(DepthOnlyVaryings input) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }
    }

    FallBack Off
}
SAMPLER(sampler_point_clamp);
SAMPLER(sampler_TrilinearRepeat);

float henyey_greenstein(float angle, float scattering)
{
    return (1.0 - angle * angle) / (4.0 * PI * pow(1.0 + scattering * scattering - (2.0 * scattering) * angle, 1.5f));
}

float get_density(float3 worldPos)
{
    float4 noise = _Fog_3D_Noise_Tex.SampleLevel(sampler_TrilinearRepeat, worldPos * 0.01 * _3D_Noise_Tiling, 0);
    float density = dot(noise, noise);
    density = saturate(density - _Density_Threshold) * _Density_Multiplier;

    return density;
}

void ComputeFog_float(float2 uv, out float4 OutColor)
{
    float4 sceneColor = SAMPLE_TEXTURE2D(_MainTex, sampler_point_clamp, uv);
    float depth = SHADERGRAPH_SAMPLE_SCENE_DEPTH(uv);
    float3 worldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);

    float3 entryPoint = _WorldSpaceCameraPos;
    float3 viewDir = worldPos - _WorldSpaceCameraPos;
    float viewLength = length(viewDir);
    float3 rayDir = normalize(viewDir);

    float2 pixelCoords = uv * _MainTex_TexelSize.zw;
    float distLimit = min(viewLength, _Max_Distance);
    float distTravelled = InterleavedGradientNoise(pixelCoords, (int)(_Time.y / max(HALF_EPS, unity_DeltaTime.x))) * _Noise_Offset;
    float transmittance = 1;
    float4 fogCol = _Fog_Color;

    while (distTravelled < distLimit)
    {
        float3 rayPos = entryPoint + rayDir * distTravelled;
        float density = get_density(rayPos);
        if (density > 0)
        {
            Light mainLight = GetMainLight(TransformWorldToShadowCoord(rayPos));
            fogCol.rgb += mainLight.color.rgb * _Light_Contribution_Color.rgb * henyey_greenstein(dot(rayDir, mainLight.direction), _Light_Scattering) * density * mainLight.shadowAttenuation * _Step_Size;
            if (mainLight.shadowAttenuation) {
                fogCol.rgb += _Light_Contribution_Offset;
            }
            transmittance *= exp(-density * _Step_Size);
        }
        distTravelled += _Step_Size;
    }

    OutColor = lerp(sceneColor, fogCol, 1.f - saturate(transmittance));

    Light mainLight = GetMainLight(TransformWorldToShadowCoord(worldPos));
}
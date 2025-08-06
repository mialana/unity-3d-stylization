SAMPLER(sampler_point_clamp);
SAMPLER(sampler_TrilinearRepeat);

void Unity_SampleGradient_float(Gradient Grad, float Time, out float4 Out)
{
    float3 color = Grad.colors[0].rgb;
    [unroll] for (int c = 1; c < 8; c++)
    {
        float colorPos = saturate((Time - Grad.colors[c - 1].w) / (Grad.colors[c].w - Grad.colors[c - 1].w)) * step(c, Grad.colorsLength - 1);
        color = lerp(color, Grad.colors[c].rgb, lerp(colorPos, step(0.01, colorPos), Grad.type));
    }
#ifndef UNITY_COLORSPACE_GAMMA
    color = SRGBToLinear(color);
#endif
    float alpha = Grad.alphas[0].x;
    [unroll] for (int a = 1; a < 8; a++)
    {
        float alphaPos = saturate((Time - Grad.alphas[a - 1].y) / (Grad.alphas[a].y - Grad.alphas[a - 1].y)) * step(a, Grad.alphasLength - 1);
        alpha = lerp(alpha, Grad.alphas[a].x, lerp(alphaPos, step(0.01, alphaPos), Grad.type));
    }
    Out = float4(color, alpha);
}

float hash31(float3 p)
{
    // Cheap 3D → 1D hash function using sine and dot
    p = frac(p * 0.3183099 + float3(0.1, 0.1, 0.1));
    p *= 17.0;
    return frac(sin(dot(p, float3(1.0, 57.0, 113.0))) * 43758.5453);
}

float henyey_greenstein(float angle, float scattering)
{
    return (1.0 - angle * angle) / (4.0 * PI * pow(abs(1.0 + scattering * scattering - (2.0 * scattering) * angle), 1.5f));
}

void get_density_and_color(float3 worldPos, Gradient FogColorGradient, out float density, out float4 color)
{
    float delta = _Time.y;
    float startTime = delta;

    float3 fogMovement = -_Fog_Direction * delta * _Fog_Speed;
    // Two noise layers, with slightly different scale and motion
    float3 pos1 = worldPos * 0.01 * _Color_3D_Tex_Tiling + fogMovement;
    float3 pos2 = worldPos * 0.025 * _Density_3D_Tex_Tiling + fogMovement * 1.3;

    // Sample raw noise values
    float base = _Density_3D_Tex.SampleLevel(sampler_TrilinearRepeat, pos1, 0).r;
    float detail = _Density_3D_Tex_Layer_2.SampleLevel(sampler_TrilinearRepeat, pos2, 0).r;

    // Weighted additive blend
    density = base + detail * 0.4; // tweak 0.4 to control detail's influence
    density = saturate(density - _Density_Threshold) * _Density_Multiplier;

    float randomOffset = lerp(-_Color_3D_Tex_Offset, _Color_3D_Tex_Offset, hash31(pos1));

    Unity_SampleGradient_float(FogColorGradient, base + randomOffset, color);
}

void ComputeFog_float(float2 uv, Gradient FogColorGradient, out float4 OutColor)
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

#ifndef SHADERGRAPH_PREVIEW
    while (distTravelled < distLimit)
    {
        float3 rayPos = entryPoint + rayDir * distTravelled;
        float density;
        float4 tintColor;
        get_density_and_color(rayPos, FogColorGradient, density, tintColor);
        if (density > 0)
        {
            Light mainLight = GetMainLight(TransformWorldToShadowCoord(rayPos));

            fogCol.rgb += mainLight.color.rgb * _Light_Contribution_Color.rgb * henyey_greenstein(dot(rayDir, mainLight.direction), _Light_Scattering) * density * mainLight.shadowAttenuation * _Step_Size;

            if (mainLight.shadowAttenuation)
            {
                density *= _Light_Contribution_Scalar;
            }

            fogCol = lerp(fogCol, tintColor, _Noise_Tint_Scalar * density);
            transmittance *= exp(-density * _Step_Size);
        }
        distTravelled += _Step_Size;
    }
#endif

    OutColor = lerp(sceneColor, fogCol, 1.f - saturate(transmittance));

    // Light mainLight = GetMainLight(TransformWorldToShadowCoord(worldPos));
}

void GetWorldPos_float(float2 uv, out float3 WorldPos)
{
    float depth = SHADERGRAPH_SAMPLE_SCENE_DEPTH(uv);
    WorldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
}
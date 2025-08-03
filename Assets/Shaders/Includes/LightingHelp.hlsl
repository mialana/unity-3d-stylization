void GetMainLight_float(float3 WorldPos, out float3 Color, out float3 Direction, out float DistanceAtten, out float ShadowAtten)
{
#ifdef SHADERGRAPH_PREVIEW
    Direction = normalize(float3(0.5, 0.5, 0));
    Color = 1;
    DistanceAtten = 1;
    ShadowAtten = 1;
#else
#if SHADOWS_SCREEN
    float4 clipPos = TransformWorldToClip(WorldPos);
    float4 shadowCoord = ComputeScreenPos(clipPos);
#else
    float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
#endif

    Light mainLight = GetMainLight(shadowCoord);
    Direction = mainLight.direction;
    Color = mainLight.color;
    DistanceAtten = mainLight.distanceAttenuation;
    ShadowAtten = mainLight.shadowAttenuation;
#endif
}

float GetSmoothnessPower(float rawSmoothness)
{
    return exp2(10 * rawSmoothness + 1);
}

void ComputeSpecularHighlight_float(float3 WorldNormal, float3 WorldViewDir, float3 LightDirection, float Diffuse, float Smoothness, float SpecularCutoff, bool IsHardSpecular, out float Specular)
{
    Specular = saturate(dot(WorldNormal, normalize(LightDirection + normalize(WorldViewDir))));
    Specular = pow(Specular, GetSmoothnessPower(Smoothness));

    if (IsHardSpecular) 
    {
        Specular = step(SpecularCutoff, Specular);
    }
    Specular *= Diffuse;
}

void ComputeAdditionalLighting_float(float3 WorldPosition, float3 WorldNormal, float3 WorldViewDir, float2 Thresholds, float3 RampedDiffuseValues, float Smoothness, float SpecularCutoff, bool IsHardSpecular, out float3 Color, out float Diffuse)
{
    Color = float3(0, 0, 0);
    Diffuse = 0;

#ifndef SHADERGRAPH_PREVIEW

    int pixelLightCount = GetAdditionalLightsCount();

    for (int i = 0; i < pixelLightCount; ++i)
    {
        Light light = GetAdditionalLight(i, WorldPosition);
        float4 tmp = unity_LightIndices[i / 4];
        uint light_i = tmp[i % 4];

        half shadowAtten = light.shadowAttenuation * AdditionalLightRealtimeShadow(light_i, WorldPosition, light.direction);

        half NdotL = saturate(dot(WorldNormal, light.direction));
        half distanceAtten = light.distanceAttenuation;

        half thisDiffuse = distanceAtten * shadowAtten * NdotL;

        half thisSpecular = pow(saturate(dot(WorldNormal, normalize(light.direction + normalize(WorldViewDir)))), GetSmoothnessPower(Smoothness));

        if (IsHardSpecular)
        {
            thisSpecular = step(SpecularCutoff, thisSpecular);
        }

        thisSpecular *= thisDiffuse;

        half rampedDiffuse = 0;

        if (thisDiffuse < Thresholds.x)
        {
            rampedDiffuse = RampedDiffuseValues.x;
        }
        else if (thisDiffuse < Thresholds.y)
        {
            rampedDiffuse = RampedDiffuseValues.y;
        }
        else
        {
            rampedDiffuse = RampedDiffuseValues.z;
        }

        if (shadowAtten * NdotL == 0)
        {
            rampedDiffuse = 0;
        }

        if (light.distanceAttenuation <= 0)
        {
            rampedDiffuse = 0.0;
        }

        Color += max(rampedDiffuse + thisSpecular, 0) * light.color.rgb;
        Diffuse += rampedDiffuse;
    }
#endif
}

void ChooseColor_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse, float2 Thresholds, out float3 OUT)
{
    if (Diffuse < Thresholds.x)
    {
        OUT = Shadow;
    }
    else if (Diffuse < Thresholds.y)
    {
        OUT = Midtone;
    }
    else
    {
        OUT = Highlight;
    }
    float outAvg = (OUT.r + OUT.g + OUT.b) / 3.f;
    // OUT = float3(outAvg, outAvg, outAvg);
}

void ChooseColor_float(float3 Highlight, float3 Shadow, float Diffuse, float Threshold, out float3 OUT)
{
    if (Diffuse < Threshold)
    {
        OUT = Shadow;
    }
    else
    {
        OUT = Highlight;
    }
}

float2 RotateUV(float2 uv, float angle)
{
    angle = angle * 0.0174533;
    float s = sin(angle);
    float c = cos(angle);
    uv -= 0.5;
    float2 rotated;
    rotated.x = uv.x * c - uv.y * s;
    rotated.y = uv.x * s + uv.y * c;
    return rotated + 0.5;
}

void TriplanarRotated_float(
    float3 Position,
    float3 Normal,
    float Tile,
    float Rotation,
    Texture2D Texture, SamplerState Sampler,
    out float4 Out)
{
    float Blend = 0.5;
    float3 Node_UV = Position * Tile;
    float3 Node_Blend = pow(abs(Normal), Blend);
    Node_Blend /= dot(Node_Blend, 1.0);

    // Apply same rotation to all projections
    float2 uvX = RotateUV(Node_UV.zy, Rotation); // X axis projection (YZ plane)
    float2 uvY = RotateUV(Node_UV.xz, Rotation); // Y axis projection (XZ plane)
    float2 uvZ = RotateUV(Node_UV.xy, Rotation); // Z axis projection (XY plane)

    float4 Node_X = SAMPLE_TEXTURE2D(Texture, Sampler, uvX);
    float4 Node_Y = SAMPLE_TEXTURE2D(Texture, Sampler, uvY);
    float4 Node_Z = SAMPLE_TEXTURE2D(Texture, Sampler, uvZ);

    Out = Node_X * Node_Blend.x + Node_Y * Node_Blend.y + Node_Z * Node_Blend.z;
}

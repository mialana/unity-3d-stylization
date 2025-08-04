SAMPLER(sampler_point_clamp);

void GetDepth_float(float2 uv, out float Depth)
{
    Depth = SHADERGRAPH_SAMPLE_SCENE_DEPTH(uv);
}

void GetNormal_float(float2 uv, out float3 Normal)
{
    Normal = SAMPLE_TEXTURE2D(_Normal_Buffer, sampler_point_clamp, uv).rgb;
}

void GetSceneColor_float(float2 uv, out float4 SceneColor)
{
    SceneColor = SAMPLE_TEXTURE2D(_MainTex, sampler_point_clamp, uv);
}

void GetLuminance_float(float2 uv, out float Luminance)
{
    float4 sceneColor;
    GetSceneColor_float(uv, sceneColor);
    Luminance = sceneColor.r * 0.3 + sceneColor.g * 0.59 + sceneColor.b * 0.11;
}

// Edge detection kernel that works by taking the sum of the squares of the differences between diagonally adjacent pixels (Roberts Cross).
float RobertsCross(float3 samples[4])
{
    const float3 difference_1 = samples[1] - samples[2];
    const float3 difference_2 = samples[0] - samples[3];
    return sqrt(dot(difference_1, difference_1) + dot(difference_2, difference_2)) * _Robert_s_Cross_Multiplier;
}

// The same kernel logic as above, but for a single-value instead of a vector3.
float RobertsCross(float samples[4])
{
    const float difference_1 = samples[1] - samples[2];
    const float difference_2 = samples[0] - samples[3];
    return sqrt(difference_1 * difference_1 + difference_2 * difference_2) * _Robert_s_Cross_Multiplier;
}

void ComputeOutlines_float(float2 uv, out float4 OUT)
{
    float2 texel_size = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);

    // Generate 4 diagonally placed samples.
    const float half_width_f = floor(_Outline_Thickness * 0.5);
    const float half_width_c = ceil(_Outline_Thickness * 0.5);

    float2 uvs[4];
    uvs[0] = uv + texel_size * float2(half_width_f, half_width_c) * float2(-1, 1);  // top left
    uvs[1] = uv + texel_size * float2(half_width_c, half_width_c) * float2(1, 1);   // top right
    uvs[2] = uv + texel_size * float2(half_width_f, half_width_f) * float2(-1, -1); // bottom left
    uvs[3] = uv + texel_size * float2(half_width_c, half_width_f) * float2(1, -1);  // bottom right

    float3 normal_samples[4];
    float depth_samples[4], luminance_samples[4];

    for (int i = 0; i < 4; i++)
    {
        GetDepth_float(uvs[i], depth_samples[i]);
        GetNormal_float(uvs[i], normal_samples[i]);
        GetLuminance_float(uvs[i], luminance_samples[i]);
    }

    // Apply edge detection kernel on the samples to compute edges.
    float edge_depth = RobertsCross(depth_samples);
    float edge_normal = RobertsCross(normal_samples);
    float edge_luminance = RobertsCross(luminance_samples);

    // Threshold the edges (discontinuity must be above certain threshold to be counted as an edge). The sensitivities are hardcoded here.

    float thisDepth;
    GetDepth_float(uv, thisDepth);
    float depth_threshold = thisDepth * _Depth_Threshold;
    edge_depth = edge_depth > depth_threshold ? 1 : 0;

    edge_normal = edge_normal > _Normal_Threshold ? 1 : 0;

    edge_luminance = edge_luminance > _Luminance_Threshold ? 1 : 0;

    // Combine the edges from depth/normals/luminance using the max operator.
    float edge = max(edge_depth, max(edge_normal, edge_luminance));

    // float edge = edge_luminance;

    // Color the edge with a custom sceneColor.
    float4 sceneColor;
    GetSceneColor_float(uv, sceneColor);
    if (_Debug_View) {
        if (edge == 0) {
            OUT = sceneColor;
        }
        else if (edge == edge_depth) {
            OUT = float4(1, 0, 0, 1);
        } else if (edge == edge_normal) {
            OUT = float4(0, 1, 0, 1);
        } else {
            OUT = float4(0, 0, 1, 1);
        }
    } 
    else {
        OUT = edge == 1 ? _Outline_Color : sceneColor;
    }
}
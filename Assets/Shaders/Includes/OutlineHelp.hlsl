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

void ComputeOutlines_Roberts_Cross_float(float2 uv, out float4 OUT)
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

    // Apply depthEdge detection kernel on the samples to compute edges.
    float edge_depth = RobertsCross(depth_samples);
    float edge_normal = RobertsCross(normal_samples);
    float edge_luminance = RobertsCross(luminance_samples);

    // Threshold the edges (discontinuity must be above certain threshold to be counted as an depthEdge). The sensitivities are hardcoded here.

    float thisDepth;
    GetDepth_float(uv, thisDepth);
    float depth_threshold = thisDepth * _Depth_Threshold;
    edge_depth = smoothstep(0, depth_threshold, edge_depth);
    edge_depth = pow(edge_luminance, _Depth_Multiplier);

    edge_normal = smoothstep(0, _Normal_Threshold, edge_normal);
    edge_normal = pow(edge_normal, _Normal_Multiplier);

    edge_luminance = smoothstep(0, _Luminance_Threshold, edge_luminance);
    edge_luminance = pow(edge_luminance, _Luminance_Multiplier);

    // Combine the edges from depth/normals/luminance using the max operator.
    float edge = max(edge_depth, max(edge_normal, edge_luminance));

    // Color the edge with a custom sceneColor.
    float4 sceneColor;
    GetSceneColor_float(uv, sceneColor);

    if (_Debug_View)
    {
        if (edge == edge_depth)
        {
            _Outline_Color = float4(1, 0, 0, 1);
        }
        else if (edge == edge_normal)
        {
            _Outline_Color = float4(0, 1, 0, 1);
        }
        else
        {
            _Outline_Color = float4(0, 0, 1, 1);
        }
    }
    OUT = edge * _Outline_Color + (1 - edge) * sceneColor;
}

static float2 sobelSamplePoints[9] = {
    float2(-1, 1),
    float2(0, 1),
    float2(1, 1),
    float2(-1, 0),
    float2(0, 0),
    float2(1, 0),
    float2(-1, -1),
    float2(0, -1),
    float2(1, -1),
};

// Weights for the x component
static float sobelXMatrix[9] = {
    -1, 0, 1,
    -2, 0, 2,
    -1, 0, 1};

// Weights for the y component
static float sobelYMatrix[9] = {
    1, 2, 1,
    0, 0, 0,
    -1, -2, -1};

// This function runs the sobel algorithm over the depth texture
void ComputeOutlines_Sobel_float(float2 uv, out float4 OUT)
{
    float2 texel_size = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);

    // Generate 4 diagonally placed samples.
    const float half_width_f = floor(_Outline_Thickness * 0.5);
    const float half_width_c = ceil(_Outline_Thickness * 0.5);

    float2 sobel = 0;

    // We have to run the sobel algorithm over the RGB channels separately
    float2 sobelR = 0;
    float2 sobelG = 0;
    float2 sobelB = 0;

    // We can unroll this loop to make it more efficient
    // The compiler is also smart enough to remove the i=4 iteration, which is always zero
    [unroll] for (int i = 0; i < 9; i++)
    {
        float2 currUV = uv + texel_size * float2(half_width_f, half_width_c) * sobelSamplePoints[i];

        float depth;
        GetDepth_float(currUV, depth);
        sobel += depth * float2(sobelXMatrix[i], sobelYMatrix[i]);

        // Sample the scene color texture
        float4 rgb;
        GetSceneColor_float(currUV, rgb);
        // Create the kernel for this iteration
        float2 kernel = float2(sobelXMatrix[i], sobelYMatrix[i]);
        // Accumulate samples for each color
        sobelR += rgb.r * kernel;
        sobelG += rgb.g * kernel;
        sobelB += rgb.b * kernel;
    }

    // Get the final sobel value
    float depthEdge = length(sobel);

    float thisDepth;
    GetDepth_float(uv, thisDepth);
    float depth_threshold = thisDepth * _Depth_Threshold;

    depthEdge = smoothstep(0, depth_threshold, depthEdge);
    depthEdge = pow(depthEdge, _Depth_Multiplier);

    // Get the final sobel value
    // Combine the RGB values by taking the one with the largest sobel value
    float rgbEdge = max(length(sobelR), max(length(sobelG), length(sobelB)));
    rgbEdge = smoothstep(0, _RGB_Threshold, rgbEdge);
    rgbEdge = pow(rgbEdge, _RGB_Multiplier);

    float edge = max(depthEdge, rgbEdge);

    float4 sceneColor;
    GetSceneColor_float(uv, sceneColor);
    if (_Debug_View)
    {
        if (edge == depthEdge)
        {
            _Outline_Color = float4(1, 0, 0, 1);
        }
        else
        {
            _Outline_Color = float4(0, 1, 0, 1);
        }
    }
    OUT = edge * _Outline_Color + (1 - edge) * sceneColor;
}
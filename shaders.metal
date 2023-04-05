/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's Metal shaders.
*/

#include <metal_stdlib>

using namespace metal;


typedef struct
{
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;



// Display a 2D texture.
vertex ColorInOut planeVertexShader(Vertex in [[stage_in]])
{
    ColorInOut out;
    out.position = float4(in.position, 0.0f, 1.0f);
    out.texCoord = in.texCoord;
    return out;
}

// Shade a 2D plane by passing through the texture inputs.
fragment float4 planeFragmentShader(ColorInOut in [[stage_in]], texture2d<float, access::sample> textureIn [[ texture(0) ]])
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::linear);
    float4 sample = textureIn.sample(colorSampler, in.texCoord);
    return sample;
}

// Shade a 2D plane by using the length of the values that are encoded in the RGBA channels.
fragment half4 planeFragmentShaderCoefs(ColorInOut in [[stage_in]], texture2d<float, access::sample> textureIn [[ texture(0) ]])
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::linear);
    float4 sample = textureIn.sample(colorSampler, in.texCoord);
    half a = length(sample.rgb);
    half b = abs(sample.a);
    return half4(a+b, b, b, 1);
}


// Convert a color value to RGB using a Jet color scheme.
static half4 getJetColorsFromNormalizedVal(half val) {
    half4 res ;
    if(val <= 0.01h)
        return half4();
    res.r = 1.5h - fabs(4.0h * val - 3.0h);
    res.g = 1.5h - fabs(4.0h * val - 2.0h);
    res.b = 1.5h - fabs(4.0h * val - 1.0h);
    res.a = 1.0h;
    res = clamp(res,0.0h,1.0h);
    return res;
}

// Shade a texture with depth values using a Jet color scheme.
//- Tag: planeFragmentShaderDepth
fragment half4 planeFragmentShaderDepth(ColorInOut in [[stage_in]], texture2d<float, access::sample> textureDepth [[ texture(0) ]])
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::nearest);
    float4 s = textureDepth.sample(colorSampler, in.texCoord);
    
    // Size the color gradient to a maximum distance of 2.5 meters.
    // The LiDAR Scanner supports a value no larger than 5.0; the
    // sample app uses a value of 2.5 to better distinguish depth
    // in smaller environments.
    half val = s.r / 2.5h;
    return half4(s[0], s[1], s[2], 1.0h);
    //return res;
}

// Shade a texture with confidence levels low, medium, and high to red, green, and blue, respectively.
fragment half4 planeFragmentShaderConfidence(ColorInOut in [[stage_in]], texture2d<float, access::sample> textureIn [[ texture(0) ]])
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::nearest);
    float4 s = textureIn.sample(colorSampler, in.texCoord);
    float res = round( 255.0f*(s.r) ) ;
    int resI = int(res);
    half4 color = half4(0.0h, 0.0h, 0.0h, 0.0h);
    if (resI == 0)
        color = half4(1.0h, 0.0h, 0.0h, 1.0h);
    else if (resI == 1)
        color = half4(0.0h, 1.0h, 0.0h, 1.0h);
    else if (resI == 2)
        color = half4(0.0h, 0.0h, 1.0h, 1.0h);
    return color;
}


// Declare a particle class that the `pointCloudVertexShader` inputs
// to `pointCloudFragmentShader`.
typedef struct
{
    float4 clipSpacePosition [[position]];
    float2 coor;
    float pSize [[point_size]];
    float depth;
    half4 color;
} ParticleVertexInOut;


// Position vertices for the point cloud view. Filters out points with
// confidence below the selected confidence value and calculates the color of a
// particle using the color Y and CbCr per vertex. Use `viewMatrix` and
// `cameraIntrinsics` to calculate the world point location of each vertex in
// the depth map.
//- Tag: pointCloudVertexShader
vertex ParticleVertexInOut pointCloudVertexShader(
    uint vertexID [[ vertex_id ]],
    texture2d<float, access::read> depthTexture [[ texture(0) ]],
    texture2d<float, access::read> confTexture [[ texture(1) ]],
    constant float4x4& viewMatrix [[ buffer(0) ]],
    constant float3x3& cameraIntrinsics [[ buffer(1) ]],
    constant int &confFilterMode [[ buffer(2) ]],
    texture2d<half> colorYtexture [[ texture(2) ]],
    texture2d<half> colorCbCrtexture [[ texture(3) ]]
    )
{ // ...
    ParticleVertexInOut out;
    uint2 pos;
    // Count the rows that are depth-texture-width wide to determine the y-value.
    pos.y = vertexID / depthTexture.get_width();
    
    // The x-position is the remainder of the y-value division.
    pos.x = vertexID % depthTexture.get_width();
    //get depth in [mm]
    float depth = depthTexture.read(pos).x * 1000.0f;
    
    // Convert confidence from normalized `float` to `int`.
    float4 conf = confTexture.read(pos);
    int confInt = int(round( 255.0f*(conf.r) )) ;
    
    // Filter points by confidence level.
    const auto visibility = confInt >= confFilterMode;
    if(visibility == false)
        depth = 0.0f;

    // Calculate the vertex's world coordinates.
    float xrw = ((int)pos.x - cameraIntrinsics[2][0]) * depth / cameraIntrinsics[0][0];
    float yrw = ((int)pos.y - cameraIntrinsics[2][1]) * depth / cameraIntrinsics[1][1];
    float4 xyzw = { xrw, yrw, depth, 1.f };

    // Project the coordinates to the view.
    float4 vecout = viewMatrix * xyzw;

    // Color the vertex.
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    out.coor = { pos.x / (depthTexture.get_width() - 1.0f), pos.y / (depthTexture.get_height() - 1.0f) };
    half y = colorYtexture.sample(textureSampler, out.coor).r;
    half2 uv = colorCbCrtexture.sample(textureSampler, out.coor).rg - half2(0.5h, 0.5h);
    // Convert YUV to RGB inline.
    half4 rgbaResult = half4(y + 1.402h * uv.y, y - 0.7141h * uv.y - 0.3441h * uv.x, y + 1.772h * uv.x, 1.0h);

    out.color = rgbaResult;
    out.clipSpacePosition = vecout;
    out.depth = depth;
    // Set the particle display size.
    out.pSize = 5.0f;
    
    return out;
}

// Shade the point cloud points by using quad particles.
fragment half4 pointCloudFragmentShader(
    ParticleVertexInOut in [[stage_in]])
{
    // Avoid drawing particles that are too close, or filtered particles that
    // have zero depth.
    if (in.depth < 1.0f)
        discard_fragment();
    else
    {
        return in.color;
    }
    return half4();
}


// Convert the Y and CbCr textures into a single RGBA texture.
kernel void convertYCbCrToRGBA(texture2d<float, access::read> colorYtexture [[texture(0)]],
                               texture2d<float, access::read> colorCbCrtexture [[texture(1)]],
                               texture2d<float, access::write> colorRGBTexture [[texture(2)]],
                               uint2 gid [[thread_position_in_grid]])
{
    float y = colorYtexture.read(gid).r;
    float2 uv = colorCbCrtexture.read(gid / 2).rg;
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture
    // coordinate.
    float4 ycbcr = float4(y, uv.x, uv.y, 1.0f);
    
    // Return the converted RGB color.
    float4 colorSample = ycbcrToRGBTransform * ycbcr;
    colorRGBTexture.write(colorSample, uint2(gid.xy));

}
kernel void getLightSource(
                                                      texture2d<float, access::read> colorRGBTexture [[texture(0)]],
                                                      device atomic_uint &x [[buffer(0)]],
                                                      device atomic_uint &y [[buffer(1)]],
                                                      device atomic_uint &counter [[buffer(2)]],
                                                      uint2 gid [[thread_position_in_grid]]
                                                      )
{
    float3 rgbResult = colorRGBTexture.read(gid).rgb;
    if (rgbResult[0] > .9 && rgbResult[1] > .9 && rgbResult[2] > .9) {
        atomic_fetch_add_explicit(&x, uint(gid.x), memory_order_relaxed);
        atomic_fetch_add_explicit(&y, uint(gid.y), memory_order_relaxed);
        atomic_fetch_add_explicit(&counter, 1, memory_order_relaxed);
    }
}

kernel void getWorldCoords(
                                                  texture2d<float, access::read> depthTexture [[ texture(0) ]],
                                                  constant float3x3 &cameraIntrinsics [[ buffer(0) ]],
                                                  constant uint &x [[buffer(1)]],
                                                  constant uint &y [[buffer(2)]],
                                                  device float3 &worldCoords [[buffer(3)]],
                                                  uint2 gid [[thread_position_in_grid]]
                                                  )
{ // ...
    // assume 1920x1440 x and y coords
    // depth is 256x192
    uint2 pos = {x, y}; // need to convert to correct coords
    
    // Get depth in mm.
    float depth = (depthTexture.read(pos).x);
    
    
    // Calculate the vertex's world coordinates.
    float xrw = ((int)pos.x - cameraIntrinsics[2][0]) * depth / cameraIntrinsics[0][0];
    float yrw = ((int)pos.y - cameraIntrinsics[2][1]) * depth / cameraIntrinsics[1][1];
    worldCoords = {xrw, yrw, -depth}; // need -depth to align w/ coordinate system
}

// Rec. 709 luma values for grayscale image conversion
constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722);
constant half4 white = half4(1.0h, 1.0h, 1.0h, 1.0h);
constant half4 black = half4(0.0h, 0.0h, 0.0h, 1.0h);

kernel void getShadowMask(
                                                  texture2d<float, access::read> colorRGBTexture [[ texture(0) ]],
                                                  texture2d<half, access::write> shadowMask [[ texture(1) ]],
                                                  uint2 gid [[thread_position_in_grid]]
                                                  )
{
    half3 rgbResult = half3(colorRGBTexture.read(gid).rgb);
    half gray = dot(rgbResult, kRec709Luma);
    if (gid.x > 1920/2 && gray > 0.05h && gray < 0.1h) { //
        shadowMask.write(white, uint2(gid.xy));
    } else {
        shadowMask.write(black, uint2(gid.xy));
    }
    
}

constant uint squareSize = 100;
kernel void getLightSourceTexture (
                                                      texture2d<half, access::read> colorRGBTexture [[ texture(0) ]],
                                                      texture2d<half, access::write> outTexture [[ texture(1) ]],
                                                      constant uint &xCenter [[buffer(0)]],
                                                      constant uint &yCenter [[buffer(1)]],
                                                      uint2 gid [[thread_position_in_grid]]
                                                      )
{
    half3 rgbResult = colorRGBTexture.read(gid).rgb;
    //float depth = depthTexture.sample(textureSampler, in.texCoord).r;
    int pointSize = 15;
    int2 pointCenter = {int(gid.x) - int(xCenter), int(gid.y) - int(yCenter)};
    bool withinXRange = pointCenter.x < pointSize && pointCenter.x > -pointSize;
    bool withinYRange = pointCenter.y < pointSize && pointCenter.y > -pointSize;
    if ((xCenter != 0 && yCenter != 0) && withinXRange && withinYRange) {
        outTexture.write(white, gid.xy);
    } else {
        if (rgbResult[0] > .9 && rgbResult[1] > .9 && rgbResult[2] > .9) {
             outTexture.write(half4(0, 0, 1.0h, 1.0h), gid.xy);
        } else {
             outTexture.write(half4(rgbResult[0], rgbResult[1], rgbResult[2], 1.0h), gid.xy);
        }
    }
}

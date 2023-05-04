/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's Metal shaders.
*/

#include <metal_stdlib>
#include <simd/simd.h>
#define RAY_MASK_PRIMARY 3

using namespace metal;
using namespace raytracing;

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

// Represents a three dimensional voxel.
struct Voxel {
    // Voxel location
    float3 loc;
    
    // insides
    uint ins;
    
    // outsides
    uint outs;
};

// Represents a three dimensional ray which will be intersected with the scene.
struct Ray {
    // Starting point
    float3 origin;
    
    float3 direction;
};


constant float3 vmin = float3(-0.15f, -0.15f, 0.3f);

constant float3 vmax = float3(0.15f, 0.15f, 0.6f);

constant float3 boxSize = abs(vmax - vmin);

constant float3 voxelCount = float3(30.0f, 30.0f, 30.0f);

float rayBoxIntersection(float3 origin, float3 direction)
{
    float tmin = 0;
    float tmax = 0;
    float tymin = 0;
    float tymax = 0;
    float tzmin = 0;
    float tzmax = 0;
    
    if (direction.x >= 0) {
        tmin = (vmin.x - origin.x) / direction.x;
        tmax = (vmax.x - origin.x) / direction.x;
    } else {
        tmin = (vmax.x - origin.x) / direction.x;
        tmax = (vmin.x - origin.x) / direction.x;
    }
  
    if (direction.y >= 0) {
        tymin = (vmin.y - origin.y) / direction.y;
        tymax = (vmax.y - origin.y) / direction.y;
    } else {
        tymin = (vmax.y - origin.y) / direction.y;
        tymax = (vmin.y - origin.y) / direction.y;
    }

    if ((tmin > tymax) || (tymin > tmax)) {
        return NAN; // doesn't intersect
    }
       
    if (tymin > tmin) tmin = tymin;
    
    if (tymax < tmax) tmax = tymax;
    
    if (direction.z >= 0) {
        tzmin = (vmin.z - origin.z) / direction.z;
        tzmax = (vmax.z - origin.z) / direction.z;
    } else {
        tzmin = (vmax.z - origin.z) / direction.z;
        tzmax = (vmin.z - origin.z) / direction.z;
    }

    if ((tmin > tzmax) || (tzmin > tmax)) {
        return NAN; // doesn't intersect
    }
    
    if (tzmin > tmin) {
        tmin = tzmin;
    }
   
    if (tzmax < tmax) {
        tmax = tzmax;
    }
    
    return tmin; // intersects
}

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

float3 coordsToWorld(float3x3 cameraIntrinsics, uint2 xy, float depth) {
    float xrw = ((int)xy.x - cameraIntrinsics[2][0]) * depth / cameraIntrinsics[0][0];
    float yrw = ((int)xy.y - cameraIntrinsics[2][1]) * depth / cameraIntrinsics[1][1];
    return {xrw, -yrw, depth}; // make depth positive--easier with algorithm?
    //return {xrw, -yrw, -depth}; // need -y, -z to align w/ arkit coordinate system
}

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
    // depth is 256x192
    uint2 pos = {x, y}; // need to convert to correct coords
    
    // Get depth in mm.
    float depth = (depthTexture.read(pos).x);
    worldCoords = coordsToWorld(cameraIntrinsics, pos, depth);
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
    if (gid.x > colorRGBTexture.get_width()/2 && gid.y > 509 && gid.y < 520) {
        shadowMask.write(white, uint2(gid.xy));
    } else {
        shadowMask.write(black, uint2(gid.xy));
    }
//    if (gid.x > colorRGBTexture.get_width()/2 && gray > 0.05h && gray < 0.1h) { //
//        shadowMask.write(white, uint2(gid.xy));
//    } else {
//        shadowMask.write(black, uint2(gid.xy));
//    }
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

kernel void LiDARToVerts(
                      texture2d<float, access::read> depthTexture [[ texture(0) ]],
                      constant float3x3 &cameraIntrinsics [[ buffer(0) ]],
                      device float3 *verts [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]])
                      //device float3 &voxel)
{
    // Since we aligned the thread count to the threadgroup size, the thread index may be out of bounds
    // of the render target size.
    // Ray we will produce
    unsigned int vertIdx = gid.y * depthTexture.get_width() + gid.x;
    device float3 &vert = verts[vertIdx];
    // Get depth in mm.
    float depth = (depthTexture.read(gid).x);
    vert = coordsToWorld(cameraIntrinsics, gid, depth);
}


// Generates rays starting from the startingPos traveling towards the mask pixels
kernel void rayKernel(texture2d<float, access::read> depthTexture [[ texture(0) ]],
                      texture2d<half, access::read> maskTexture [[ texture(1) ]],
                      device Ray *rays [[buffer(0)]],
                      constant float3 &startingPos [[buffer(1)]],
                      constant float3x3 &cameraIntrinsics [[buffer(2)]],
                      device float3 &orig [[buffer(3)]],
                      device float3 &dir [[buffer(4)]],
                      uint2 gid [[thread_position_in_grid]])
{
    half3 rgbResult = maskTexture.read(gid).rgb;
    if (rgbResult.r == white.r && rgbResult.g == white.g && rgbResult.b == white.b) {
        device Ray &ray = rays[gid.x + gid.y * maskTexture.get_width()];
        float3 maskWorldPos = coordsToWorld(cameraIntrinsics, gid, depthTexture.read(gid).x);
        ray.origin = startingPos;
        ray.direction = normalize(maskWorldPos - startingPos);
        orig = ray.origin;
        dir = ray.direction;
    }
}

// Generates rays starting from the startingPos traveling towards the mask pixels
kernel void intersect(device Ray *rays [[buffer(0)]],
                      //device atomic_uint *ins [[buffer(1)]],
                      device atomic_uint *ins [[buffer(1)]],
                      constant uint &width [[buffer(2)]],
                      uint2 gid [[thread_position_in_grid]])
{
    device Ray &ray = rays[gid.x + gid.y * width];
    if (ray.origin.x != 0.0f && ray.origin.y != 0.0f && ray.origin.z != 0.0f && ray.direction.x != 0.0f && ray.direction.y != 0.0f && ray.direction.z != 0.0f) {
        float tmin = rayBoxIntersection(ray.origin, ray.direction);

        if (!isnan(tmin)) {
            
            float3 vmin = float3(-0.15f, -0.15f, 0.3f);

            float3 vmax = float3(0.15f, 0.15f, 0.6f);

            float3 boxSize = abs(vmax - vmin);

            float3 voxelCount = float3(30.0f, 30.0f, 30.0f);
            
            //ins[0] = (vmin.x - ray.origin.x) / ray.direction.x;
            if (tmin < 0) tmin = 0;

            float3 start = ray.origin + tmin * ray.direction;
            
            float x = floor(((start.x-vmin.x)/boxSize.x)*voxelCount.x);
            float y = floor(((start.y-vmin.y)/boxSize.y)*voxelCount.x);
            float z = floor(((start.z-vmin.z)/boxSize.z)*voxelCount.x);
            float tVoxelX = 0;
            float tVoxelY = 0;
            float tVoxelZ = 0;
            float stepX = 0;
            float stepY = 0;
            float stepZ = 0;
            
            if (x == (voxelCount.x)) x = x-1;
            if (y == (voxelCount.y)) y = y-1;
            if (z == (voxelCount.z)) z = z-1;
            
            if (ray.direction.x >= 0) {
                tVoxelX = x / voxelCount.x;
                stepX = 1;
            } else {
                tVoxelX = (x-1) / voxelCount.x;
                stepX = -1;
            }

            if (ray.direction.y >= 0) {
                tVoxelY = y / voxelCount.y;
                stepY = 1;
            } else {
                tVoxelY = (y-1) / voxelCount.y;
                stepY = -1;
            }
            
            if (ray.direction.z >= 0) {
                tVoxelZ = z / voxelCount.z;
                stepZ = 1;
            } else {
                tVoxelZ = (z-1) / voxelCount.z;
                stepZ = -1;
            }
                    
            float voxelMaxX  = vmin.x + tVoxelX * boxSize.x;
            float voxelMaxY  = vmin.y + tVoxelY * boxSize.y;
            float voxelMaxZ  = vmin.z + tVoxelZ * boxSize.z;

            float tMaxX      = tmin + (voxelMaxX-start.x) / ray.direction.x;
            float tMaxY      = tmin + (voxelMaxY-start.y) / ray.direction.y;
            float tMaxZ      = tmin + (voxelMaxZ-start.z) / ray.direction.z;
            
            float voxelSizeX = boxSize.x / voxelCount.x;
            float voxelSizeY = boxSize.y / voxelCount.y;
            float voxelSizeZ = boxSize.z / voxelCount.z;
            
            float tDeltaX    = voxelSizeX / abs(ray.direction.x);
            float tDeltaY    = voxelSizeY / abs(ray.direction.y);
            float tDeltaZ    = voxelSizeZ / abs(ray.direction.z);
                    
            while ((x < voxelCount.x) && (x >= 0) && (y < voxelCount.y) && (y >= 0) && (z < voxelCount.z) && (z >= 0)) {
                // add 1 to value
                //ins[0] = 5;
                //atomic_fetch_add_explicit(&ins[uint(0)], 1, memory_order_relaxed);
                atomic_fetch_add_explicit(&ins[uint(x + y * voxelCount.x + z * voxelCount.x * voxelCount.y)], 1, memory_order_relaxed);
                if (tMaxX < tMaxY) {
                    if (tMaxX < tMaxZ) {
                        x = x + stepX;
                        tMaxX = tMaxX + tDeltaX;
                    } else {
                        z = z + stepZ;
                        tMaxZ = tMaxZ + tDeltaZ;
                    }
                } else {
                    if (tMaxY < tMaxZ) {
                        y = y + stepY;
                        tMaxY = tMaxY + tDeltaY;
                    } else {
                        z = z + stepZ;
                        tMaxZ = tMaxZ + tDeltaZ;
                    }
                }
            }
        }
    }
}

// create cube geometry
void populateGeometryBuffersAtIndex(device float3 *vertexData, device uint *indexData, float index) {
    float3 vmin = float3(-0.15f, -0.15f, 0.3f);

    float3 vmax = float3(0.15f, 0.15f, 0.6f);

    float3 boxSize = abs(vmax - vmin);

    float3 voxelCount = float3(30.0f, 30.0f, 30.0f);
    
    uint vertexIndex = uint(index) * 8; // 8 vertices in a cube
    uint indiceIndex = uint(index) * 36; // 12 triangles in a cube triangle strip, 3 indices per strip
    float zIndex = fmod(index, voxelCount.z);
    float yIndex = fmod((index / voxelCount.z), voxelCount.y);
    float xIndex = index / (voxelCount.y * voxelCount.z);
    float voxelSize = boxSize.x / voxelCount.x;
    float voxelHalfSize = voxelSize / 2.0;
    float w = voxelHalfSize;
    float h = voxelHalfSize;
    float l = voxelHalfSize;
    float x = xIndex * voxelSize + vmin.x + voxelHalfSize;
    float y = -(yIndex * voxelSize + vmin.y + voxelHalfSize);
    float z = -(zIndex * voxelSize + vmin.z + voxelHalfSize);
    // top 4 vertices
    vertexData[vertexIndex] = float3(x - w, y - h, z - l);
    vertexData[vertexIndex+1] = float3(x + w, y - h, z - l);
    vertexData[vertexIndex+2] = float3(x + w, y - h, z + l);
    vertexData[vertexIndex+3] = float3(x - w, y - h, z + l);
    // bottom 4 vertices
    vertexData[vertexIndex+4] = float3(x - w, y + h, z - l);
    vertexData[vertexIndex+5] = float3(x + w, y + h, z - l);
    vertexData[vertexIndex+6] = float3(x + w, y + h, z + l);
    vertexData[vertexIndex+7] = float3(x - w, y + h, z + l);
    // bottom face
    indexData[indiceIndex] = vertexIndex + 0;
    indexData[indiceIndex+1] = vertexIndex + 1;
    indexData[indiceIndex+2] = vertexIndex + 3;
    indexData[indiceIndex+3] = vertexIndex + 3;
    indexData[indiceIndex+4] = vertexIndex + 1;
    indexData[indiceIndex+5] = vertexIndex + 2;
    // left face
    indexData[indiceIndex+6] = vertexIndex + 0;
    indexData[indiceIndex+7] = vertexIndex + 3;
    indexData[indiceIndex+8] = vertexIndex + 4;
    indexData[indiceIndex+9] = vertexIndex + 4;
    indexData[indiceIndex+10] = vertexIndex + 3;
    indexData[indiceIndex+11] = vertexIndex + 7;
    // right face
    indexData[indiceIndex+12] = vertexIndex + 1;
    indexData[indiceIndex+13] = vertexIndex + 5;
    indexData[indiceIndex+14] = vertexIndex + 2;
    indexData[indiceIndex+15] = vertexIndex + 2;
    indexData[indiceIndex+16] = vertexIndex + 5;
    indexData[indiceIndex+17] = vertexIndex + 6;
    // top face
    indexData[indiceIndex+18] = vertexIndex + 4;
    indexData[indiceIndex+19] = vertexIndex + 7;
    indexData[indiceIndex+20] = vertexIndex + 5;
    indexData[indiceIndex+21] = vertexIndex + 5;
    indexData[indiceIndex+22] = vertexIndex + 7;
    indexData[indiceIndex+23] = vertexIndex + 6;
    // front face
    indexData[indiceIndex+24] = vertexIndex + 3;
    indexData[indiceIndex+25] = vertexIndex + 2;
    indexData[indiceIndex+26] = vertexIndex + 7;
    indexData[indiceIndex+27] = vertexIndex + 7;
    indexData[indiceIndex+28] = vertexIndex + 2;
    indexData[indiceIndex+29] = vertexIndex + 6;
    // back face
    indexData[indiceIndex+30] = vertexIndex + 0;
    indexData[indiceIndex+31] = vertexIndex + 4;
    indexData[indiceIndex+32] = vertexIndex + 1;
    indexData[indiceIndex+33] = vertexIndex + 1;
    indexData[indiceIndex+34] = vertexIndex + 4;
    indexData[indiceIndex+35] = vertexIndex + 5;
}

bool occupied(float m, float n) {
    return true;
    //return m > 0;
    float eta = .1; // Probability occupied voxel is traced to illuminated region (miss probability)
    float xi = .5; // Probability that an empty voxel is traced to shadow (probability false alarm)
    float p0 = 0.9; // Prior probability that any voxel is empty
    float p1 = 0.05; // Prior probability that any voxel is occupied
    float T = 0.9; // Probabilitzy threshold to decide that voxel is occupied
    float probablisticOccupancy = p1*(pow(eta, m))*(pow((1.0-eta), n))/(p0*(pow((1.0-xi), m))*(pow(xi, n)) + p1*(pow(eta, m))*(pow((1.0-eta), n)));
    return probablisticOccupancy > T;
}

// Populate voxels for display.
kernel void samplePopulateVoxels(device float3 *vertexData [[buffer(0)]],
                                 device uint *indexData [[buffer(1)]],
                                 device uint *ins [[buffer(2)]], // can i make this non-atomic? think so
                                 device uint *outs [[buffer(3)]],
                                 uint3 gid [[thread_position_in_grid]]) {
    uint x = gid.x;
    uint y = gid.y;
    uint z = gid.z;
    float3 voxelCount = float3(30.0f, 30.0f, 30.0f);
    if (x >= uint(voxelCount.x) || y >= uint(voxelCount.y) || z >= uint(voxelCount.z)) { // chance for thread vals to be larger than our bounds
        return;
    }
//   sphere test
//    if ((uint(x - 15) * uint(x - 15) + uint(y - 15) * uint(y - 15) + uint(z - 15) * uint(z - 15)) > 25) {
//        return;
//    }
    float index = x + y * voxelCount.x + z * voxelCount.x * voxelCount.y;
    float m = float(ins[uint(index)]);
    float n = float(outs[uint(index)]);
    if (occupied(m, n)) {
        populateGeometryBuffersAtIndex(vertexData, indexData, index);
    }
}


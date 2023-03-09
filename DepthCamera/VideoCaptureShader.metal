//
//  VideoCaptureShader.metal
//  DepthCamera
//
//  Created by Tianjian Xu on 3/1/23.
//

#include <metal_stdlib>
#include "Types.h"
using namespace metal;

vertex RasterizedData videoCaptureVertexShader(uint vID [[ vertex_id ]],
                                               device const VertexIn* vertices [[ buffer(0)]]) {
    VertexIn vIn = vertices[vID];
    
    RasterizedData rd;
    rd.position = float4(vIn.position, 0.0f, 1.0f);
    rd.uv = vIn.uv;
    return rd;
}

fragment half4 videoCaptureFragmentShader(RasterizedData rd [[ stage_in ]],
                                          sampler sampler [[ sampler(0) ]],
                                          texture2d<float> videoTextureY [[ texture(0) ]],
                                          texture2d<float> videoTextureCrBr [[ texture(1) ]]) {
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    float4 ycbcr = float4(videoTextureY.sample(sampler, rd.uv).r,
                          videoTextureCrBr.sample(sampler, rd.uv).rg,
                          1.0f);
    float4 color = ycbcrToRGBTransform * ycbcr;
    return half4(color);
}



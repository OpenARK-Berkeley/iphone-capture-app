//
//  DepthCaptureShader.metal
//  DepthCamera
//
//  Created by Tianjian Xu on 3/2/23.
//

#include <metal_stdlib>
#include "Types.h"
using namespace metal;

vertex RasterizedData depthCaptureVertexShader(uint vID [[ vertex_id ]],
                                               device const VertexIn* vertices [[ buffer(0)]]) {
    VertexIn vIn = vertices[vID];
    
    RasterizedData rd;
    rd.position = float4(vIn.position, 0.0f, 1.0f);
    rd.uv = vIn.uv;
    return rd;
}

fragment half4 depthCaptureWithConfidenceFragmentShader(RasterizedData rd [[ stage_in ]],
                                                        constant uint &confidenceThreshold [[ buffer(0) ]],
                                                        sampler sampler [[ sampler(0) ]],
                                                        texture2d<float> depthTexture [[ texture(0) ]],
                                                        texture2d<uint> depthConfidence [[ texture(1) ]]) {
    
    uint confidence = depthConfidence.sample(sampler, rd.uv).r;
    if (confidence < confidenceThreshold) {
        discard_fragment();
    }
    
    float depth = depthTexture.sample(sampler, rd.uv).r;
    half4 color = half4(depth, depth, depth, 1.0f);
    return color;
}

fragment half4 depthCaptureWithoutConfidenceFragmentShader(RasterizedData rd [[ stage_in ]],
                                                           sampler sampler [[ sampler(0) ]],
                                                           texture2d<float> depthTexture [[ texture(0) ]]) {
    float depth = depthTexture.sample(sampler, rd.uv).r;
    half4 color = half4(depth, depth, depth, 1.0f);
    return color;
}



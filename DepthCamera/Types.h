//
//  Types.h
//  DepthCamera
//
//  Created by Tianjian Xu on 3/2/23.
//

#ifndef Types_h
#define Types_h

struct VertexIn {
    float2 position;
    float2 uv;
};

struct RasterizedData {
    float4 position [[ position ]];
    float2 uv;
};

#endif /* Types_h */

//
//  CaptureRenderer.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/2/23.
//

import MetalKit

enum TextureType {
    case depth, depthConfidence, videoY, videoCrBr
}

protocol CaptureRenderer: MTKViewDelegate {
    var textures: [TextureType: MTLTexture?] { get set }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    
    func draw(in view: MTKView)
}

struct Vertex {
    var position: simd_float2
    var uv: simd_float2
}

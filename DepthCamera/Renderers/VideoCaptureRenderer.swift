//
//  VideoCaptureRenderer.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/2/23.
//

import MetalKit

class VideoCaptureRenderer: NSObject {
    
    var globals = GlobalVariables.instance
    var textures: [TextureType : MTLTexture?] = [:]
    
    lazy var device: MTLDevice! = globals.device
    lazy var commandQueue: MTLCommandQueue! = device.makeCommandQueue()
    lazy var library: MTLLibrary! = device.makeDefaultLibrary()
    
    lazy var vertexFunction: MTLFunction! = library.makeFunction(name: "videoCaptureVertexShader")
    lazy var fragmentFunction: MTLFunction! = library.makeFunction(name: "videoCaptureFragmentShader")
    
    lazy var vertexBytes = [
        Vertex(position: simd_float2(-1, -1), uv: simd_float2(1, 1)),
        Vertex(position: simd_float2( 1,  1), uv: simd_float2(0, 0)),
        Vertex(position: simd_float2(-1,  1), uv: simd_float2(0, 1)),
        
        Vertex(position: simd_float2(-1, -1), uv: simd_float2(1, 1)),
        Vertex(position: simd_float2( 1, -1), uv: simd_float2(1, 0)),
        Vertex(position: simd_float2( 1,  1), uv: simd_float2(0, 0)),
    ]
    lazy var vertexBuffer: MTLBuffer! = device.makeBuffer(bytes: vertexBytes, length: vertexBytes.count * MemoryLayout<Vertex>.stride)
    
    lazy var samplerState: MTLSamplerState! = {
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.magFilter = .linear
        samplerDesc.minFilter = .linear
        samplerDesc.minFilter = .linear
        return device.makeSamplerState(descriptor: samplerDesc)
    }()
}

// MARK: Handle video capture rendering
extension VideoCaptureRenderer: CaptureRenderer {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        guard let videoTextureY = textures[.videoY], let videoTextureCrCb = textures[.videoCrBr] else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderCommandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipelineDescriptor.vertexFunction = vertexFunction
        renderPipelineDescriptor.fragmentFunction = fragmentFunction
        
        let renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        renderCommandEncoder?.setRenderPipelineState(renderPipelineState)
        renderCommandEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder?.setFragmentTexture(videoTextureY, index: 0)
        renderCommandEncoder?.setFragmentTexture(videoTextureCrCb, index: 1)
        renderCommandEncoder?.setFragmentSamplerState(samplerState, index: 0)
        
        renderCommandEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexBytes.count)
        
        renderCommandEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}

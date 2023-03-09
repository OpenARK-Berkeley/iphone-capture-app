//
//  DepthCaptureRenderer.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/2/23.
//

import MetalKit

class DepthCaptureRenderer: NSObject {
    
    var globals = GlobalVariables.instance
    var textures: [TextureType : MTLTexture?] = [:]
    
    lazy var device: MTLDevice! = globals.device
    lazy var commandQueue: MTLCommandQueue! = device.makeCommandQueue()
    lazy var library: MTLLibrary! = device.makeDefaultLibrary()
    
    var confidenceThreshold: UInt = 0
    lazy var vertexFunction: MTLFunction! = library.makeFunction(name: "depthCaptureVertexShader")
    lazy var fragmentFunctionWithConfidence: MTLFunction! = library.makeFunction(name: "depthCaptureWithConfidenceFragmentShader")
    lazy var fragmentFunctionWithoutConfidence: MTLFunction! = library.makeFunction(name: "depthCaptureWithoutConfidenceFragmentShader")
    
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
        samplerDesc.magFilter = .nearest
        samplerDesc.minFilter = .nearest
        samplerDesc.minFilter = .nearest
        return device.makeSamplerState(descriptor: samplerDesc)
    }()
}

// MARK: Handle depth capture rendering
extension DepthCaptureRenderer: CaptureRenderer {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        guard let depthTexture = textures[.depth], let depthConfidenceTexture = textures[.depthConfidence] else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderCommandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipelineDescriptor.vertexFunction = vertexFunction
        if globals.useDepthConfidence {
            renderPipelineDescriptor.fragmentFunction = fragmentFunctionWithConfidence
        } else {
            renderPipelineDescriptor.fragmentFunction = fragmentFunctionWithoutConfidence
        }
        
        let renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        renderCommandEncoder?.setRenderPipelineState(renderPipelineState)
        renderCommandEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder?.setFragmentTexture(depthTexture, index: 0)
        renderCommandEncoder?.setFragmentSamplerState(samplerState, index: 0)
        
        if globals.useDepthConfidence {
            confidenceThreshold = UInt(globals.depthConfidence.rawValue)
            renderCommandEncoder?.setFragmentBytes(&confidenceThreshold, length: MemoryLayout<UInt>.size, index: 0)
            renderCommandEncoder?.setFragmentTexture(depthConfidenceTexture, index: 1)
        }
        
        
        renderCommandEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexBytes.count)
        
        renderCommandEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}

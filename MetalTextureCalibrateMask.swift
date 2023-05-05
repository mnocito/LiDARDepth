//
//  MetalTextureCalibrateMask.swift
//  pointCloudSample
//
//  Created by Marco Nocito on 3/21/23.
//  Copyright © 2023 Apple. All rights reserved.
//

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view that displays the RGB image.
*/

import Foundation
import SwiftUI
import MetalKit
import Metal

//- Tag: CoordinatorDepth
final class CoordinatorMask: MTKCoordinator {
    init(maskContent: MetalTextureContent) {
        super.init(content: maskContent)
    }
    override func prepareFunctions() {
        guard let metalDevice = mtkView.device else { fatalError("Expected a Metal device.") }
        do {
            let library = EnvironmentVariables.shared.metalLibrary
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "planeVertexShader")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "planeFragmentShader")
            pipelineDescriptor.vertexDescriptor = createPlaneMetalVertexDescriptor()
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Unexpected error: \(error).")
        }
    }
    override func setupView(mtkView: MTKView) {
        self.mtkView = mtkView
        self.mtkView.preferredFramesPerSecond = 60
        self.mtkView.isOpaque = true
        self.mtkView.framebufferOnly = false
        self.mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.mtkView.drawableSize = mtkView.frame.size
        self.mtkView.enableSetNeedsDisplay = false
        self.mtkView.colorPixelFormat = .bgra8Unorm
        self.mtkView.autoResizeDrawable = true
        self.mtkView.depthStencilPixelFormat = .depth32Float
        self.mtkView.contentMode = .scaleAspectFit
        self.mtkView.device = EnvironmentVariables.shared.metalDevice
        self.metalCommandQueue = EnvironmentVariables.shared.metalCommandQueue
        prepareFunctions()
    }

}

struct MetalTextureCalibrateMask: UIViewRepresentable {
    var content: MetalTextureContent
    
    func makeCoordinator() -> CoordinatorMask {
        CoordinatorMask(maskContent: content)
    }
    
    func makeUIView(context: UIViewRepresentableContext<MetalTextureCalibrateMask>) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.backgroundColor = context.environment.colorScheme == .dark ? .black : .white
        context.coordinator.setupView(mtkView: mtkView)
        return mtkView
    }
    
    // `UIViewRepresentable` requires this implementation; however, the sample
    // app doesn't use it. Instead, `MTKView.delegate` handles display updates.
    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MetalTextureCalibrateMask>) {
        
    }
}

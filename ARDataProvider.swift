/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A utility class that provides processed depth information.
*/

import Foundation
import SwiftUI
import Combine
import ARKit
import Accelerate
import MetalPerformanceShaders
import simd

// Wrap the `MTLTexture` protocol to reference outputs from ARKit.
final class MetalTextureContent {
    var texture: MTLTexture?
}

enum IBOError: Error {
    // Throw when no light source is found
    case lightSourceNotFound
    
    // Throw when ARKit isn't in reconstruction mode
    case ARKitNotReconstructing

    // Throw in all other cases
    case unexpected(code: Int)
}
// Enable `CVPixelBuffer` to output an `MTLTexture`.
extension CVPixelBuffer {
    
    func texture(withFormat pixelFormat: MTLPixelFormat, planeIndex: Int, addToCache cache: CVMetalTextureCache) -> MTLTexture? {
        
        let width = CVPixelBufferGetWidthOfPlane(self, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(self, planeIndex)
        
        var cvtexture: CVMetalTexture?
        _ = CVMetalTextureCacheCreateTextureFromImage(nil, cache, self, nil, pixelFormat, width, height, planeIndex, &cvtexture)
        let texture = CVMetalTextureGetTexture(cvtexture!)
        
        return texture
        
    }
    
}

// Collect AR data using a lower-level receiver. This class converts AR data
// to a Metal texture, optionally upscaling depth data using a guided filter,
// and implements `ARDataReceiver` to respond to `onNewARData` events.
final class ARProvider: ARDataReceiver {
    // Set the destination resolution for the upscaled algorithm.
    let upscaledWidth = 960
    let upscaledHeight = 760

    // Set the original depth size.
    var origDepthWidth = 256
    let origDepthHeight = 192

    // Set the original color size.
    let origColorWidth = 1920
    let origColorHeight = 1440
    
    // Set voxel details.
    let voxelsPerSide = 80
    let vertCount: Int! // TODO: not make magic number later, doesn't port over to Metal version
    let vertsPerVoxel = 8
    let indicesPerVoxel = 36
    let numVertices: Int!
    let numIndices: Int!
    
    // Set min and max grayscale values for our mask
    var minGray: simd_float1 = 0.01
    var maxGray: simd_float1 = 0.4222
    var xMin: simd_float1 = 15
    var xMax: simd_float1 = 489
    var yMin: simd_float1 = 15
    var yMax: simd_float1 = 704
    var sideLen: simd_float1 = 1313
    var xMinL: simd_float1 = 15
    var xMaxL: simd_float1 = 489
    var yMinL: simd_float1 = 15
    var yMaxL: simd_float1 = 704
    var sideLenL: simd_float1 = 1313
    var xMinR: simd_float1 = 1284
    var xMaxR: simd_float1 = 1911
    var yMinR: simd_float1 = 425
    var yMaxR: simd_float1 = 62
    var sideLenR: simd_float1 = 532
    var blurSigma: Float = 5
    var calibrateMask = false
    
    
    let arReceiver = ARReceiver()
    var lastArData: ARData?
    let depthContent = MetalTextureContent()
    let confidenceContent = MetalTextureContent()
    let colorYContent = MetalTextureContent()
    let colorCbCrContent = MetalTextureContent()
    let upscaledCoef = MetalTextureContent()
    let downscaledRGB = MetalTextureContent()
    let colorRGB = MetalTextureContent()
    let colorRGBMasked = MetalTextureContent()
    let upscaledConfidence = MetalTextureContent()
    
    var LightSources: [LightSource] = []
    var ShadowMasks: [ShadowMask] = []
    var Voxels: [[[Voxel]]] = []
    var maskTexture: MTLTexture
    var maskTextureDownscaled: MTLTexture
    let coefTexture: MTLTexture
    let destDepthTexture: MTLTexture
    let voxelIns: MTLBuffer
    let voxelOuts: MTLBuffer
    let voxelInsTemp: MTLBuffer
    let voxelOutsTemp: MTLBuffer
    let vertBuffer: MTLBuffer
    let indBuffer: MTLBuffer
    let destConfTexture: MTLTexture
    let colorRGBTexture: MTLTexture
    let colorRGBMaskedTexture: MTLTexture
    let colorRGBTextureDownscaled: MTLTexture
    let colorRGBTextureDownscaledLowRes: MTLTexture
    let colorRGBTextureBlurred: MTLTexture
    let colorRGBTextureBlurredDownscaled: MTLTexture
    var blurKernel: MPSImageGaussianBlur!
    
    // Enable or disable depth upsampling.
    public var isToUpsampleDepth: Bool = false {
        didSet {
            processLastArData()
        }
    }
    
    // Enable or disable smoothed-depth upsampling.
    public var isUseSmoothedDepthForUpsampling: Bool = false {
        didSet {
            processLastArData()
        }
    }
    
    func fillMaskTexture() {
        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        blurKernel.encode(commandBuffer: cmdBuffer,
                      sourceTexture: colorRGBTexture,
                      destinationTexture: colorRGBTextureBlurred)
        mpsScaleFilter?.encode(commandBuffer: cmdBuffer, sourceTexture: colorRGBTextureBlurred,
                               destinationTexture: colorRGBTextureBlurredDownscaled)
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
        var xMinInt = UInt32(xMin/7.5)
        var xMaxInt = UInt32(xMax/7.5)
        var yMinInt = UInt32(yMin/7.5)
        var yMaxInt = UInt32(yMax/7.5)
        var sideLenInt = UInt32(sideLen/7.5)
        computeEncoder.setComputePipelineState(RGBToMaskPipelineComputeState!)
        computeEncoder.setTexture(colorRGBTextureBlurredDownscaled, index: 0)
        computeEncoder.setTexture(maskTextureDownscaled, index: 1)
        computeEncoder.setBytes(&minGray, length: MemoryLayout<simd_float1>.stride, index: 0)
        computeEncoder.setBytes(&maxGray, length: MemoryLayout<simd_float1>.stride, index: 1)
        computeEncoder.setBytes(&xMinInt, length: MemoryLayout<UInt32>.stride, index: 2)
        computeEncoder.setBytes(&xMaxInt, length: MemoryLayout<UInt32>.stride, index: 3)
        computeEncoder.setBytes(&yMinInt, length: MemoryLayout<UInt32>.stride, index: 4)
        computeEncoder.setBytes(&yMaxInt, length: MemoryLayout<UInt32>.stride, index: 5)
        computeEncoder.setBytes(&sideLenInt, length: MemoryLayout<UInt32>.stride, index: 6)
        let threadgroupSize = MTLSizeMake(RGBToMaskPipelineComputeState!.threadExecutionWidth,
                                          RGBToMaskPipelineComputeState!.maxTotalThreadsPerThreadgroup / RGBToMaskPipelineComputeState!.threadExecutionWidth, 1)
        let threadgroupCount = MTLSize(width: Int(ceil(Float(origDepthWidth) / Float(threadgroupSize.width))),
                                       height: Int(ceil(Float(origDepthHeight) / Float(threadgroupSize.height))),
                                       depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
    }
    
    func getLightSourceCoords() throws -> LightSource {
        let lightSourceTexture = ARProvider.createTexture(metalDevice: metalDevice, width: origColorWidth, height: origColorHeight,
                                                   usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
        let x = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size, options: [])!
        let y = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size, options: [])!
        let counter = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size, options: [])!
        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { throw MTLCommandBufferError(.invalidResource) }
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { throw MTLCommandBufferError(.invalidResource) }
        computeEncoder.setComputePipelineState(RGBToLightSourceXYCoordsPipelineComputeState!)
        computeEncoder.setTexture(colorRGBTexture, index: 0)
        computeEncoder.setBuffer(x, offset: 0, index: 0)
        computeEncoder.setBuffer(y, offset: 0, index: 1)
        computeEncoder.setBuffer(counter, offset: 0, index: 2)
        var threadgroupSize = MTLSizeMake(RGBToLightSourceXYCoordsPipelineComputeState!.threadExecutionWidth,
                                          RGBToLightSourceXYCoordsPipelineComputeState!.maxTotalThreadsPerThreadgroup / RGBToLightSourceXYCoordsPipelineComputeState!.threadExecutionWidth, 1)
        var threadgroupCount = MTLSize(width: Int(ceil(Float(colorRGBTexture.width) / Float(threadgroupSize.width))),
                                       height: Int(ceil(Float(colorRGBTexture.height) / Float(threadgroupSize.height))),
                                       depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        let counterInt = counter.contents().load(as: UInt32.self)
        var xInt = x.contents().load(as: UInt32.self)
        var yInt = y.contents().load(as: UInt32.self)
        if (counterInt == 0) {
            throw IBOError.lightSourceNotFound
        }
        xInt = xInt/counterInt
        yInt = yInt/counterInt
//        xInt = 391
//        yInt = 509
//        print("xy")
//        print(xInt)
//        print(yInt)
        var cameraIntrinsics = lastArData!.cameraIntrinsics
        let scaleRes = simd_float2(x: Float(lastArData!.cameraResolution.width) / Float(origDepthWidth),
                                   y: Float(lastArData!.cameraResolution.height) / Float(origDepthHeight))
        cameraIntrinsics[0][0] /= scaleRes.x
        cameraIntrinsics[1][1] /= scaleRes.y

        cameraIntrinsics[2][0] /= scaleRes.x
        cameraIntrinsics[2][1] /= scaleRes.y
//        print("intr")
//        print(cameraIntrinsics)
        // send coordinate and rgbtexture functions to gpu (messy code right now, sorry)
        let floatBuff = metalDevice.makeBuffer(length: MemoryLayout<simd_float3>.size, options: [])!
        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { throw MTLCommandBufferError(.invalidResource) }
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { throw MTLCommandBufferError(.invalidResource) }
        computeEncoder.setComputePipelineState(LightSourceRGBToTexturePipelineComputeState!)
        computeEncoder.setTexture(colorRGBTexture, index: 0)
        computeEncoder.setTexture(lightSourceTexture, index:1)
        computeEncoder.setBytes(&xInt, length: MemoryLayout<UInt32>.stride, index: 0)
        computeEncoder.setBytes(&yInt, length: MemoryLayout<UInt32>.stride, index: 1)
        threadgroupSize = MTLSizeMake(LightSourceRGBToTexturePipelineComputeState!.threadExecutionWidth,
                                      LightSourceRGBToTexturePipelineComputeState!.maxTotalThreadsPerThreadgroup / LightSourceRGBToTexturePipelineComputeState!.threadExecutionWidth, 1)
        threadgroupCount = MTLSize(width: Int(ceil(Float(colorRGBTexture.width) / Float(threadgroupSize.width))),
                                       height: Int(ceil(Float(colorRGBTexture.height) / Float(threadgroupSize.height))),
                                       depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        // downscale to depth res
        xInt = UInt32(Double(xInt) / 7.5)
        yInt = UInt32(Double(yInt) / 7.5)
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { throw MTLCommandBufferError(.invalidResource) }
        computeEncoder.setComputePipelineState(LightSourceXYCoordsToWorldCoordsPipelineComputeState!)
        computeEncoder.setTexture(depthContent.texture, index: 0)
        computeEncoder.setBytes(&cameraIntrinsics, length: MemoryLayout<matrix_float3x3>.stride, index: 0)
        computeEncoder.setBytes(&xInt, length: MemoryLayout<UInt32>.stride, index: 1)
        computeEncoder.setBytes(&yInt, length: MemoryLayout<UInt32>.stride, index: 2)
        computeEncoder.setBuffer(floatBuff, offset: 0, index: 3)
        threadgroupSize = MTLSizeMake(16, 16, 1)
        threadgroupCount = MTLSize(width: 1, height: 1, depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        let worldCoords = floatBuff.contents().load(as: simd_float3.self)
        //print(worldCoords)
        let lightSourceContent = MetalTextureContent()
        lightSourceContent.texture = lightSourceTexture
        return LightSource(texture: lightSourceContent, worldCoords: worldCoords)
    }
    
    func captureFrame() throws {
        if !arReceiver.isReconstructing {
            throw IBOError.ARKitNotReconstructing
        }
        do {
            let lightSource = try getLightSourceCoords()
            LightSources.append(lightSource)
        } catch {
            throw IBOError.lightSourceNotFound
        }
        framesCaptured += 1
        maskTexture = ARProvider.createTexture(metalDevice: metalDevice, width: origColorWidth, height: origColorHeight,
                                               usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
        maskTextureDownscaled = ARProvider.createTexture(metalDevice: metalDevice, width: origDepthWidth, height: origDepthHeight,
                                               usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
        fillMaskTexture()
        let maskContent = MetalTextureContent()
        maskContent.texture = maskTextureDownscaled//maskTexture
        let cameraIntrinsics = lastArData!.cameraIntrinsics
        let mask = ShadowMask(mask: maskContent, depthTexture: depthContent.texture!, cameraIntrinsics: cameraIntrinsics)
        ShadowMasks.append(mask)
        rayTraceLastFrame()
        
    }
    @Published var framesCaptured = 0
    // metal const
    let rayStride = MemoryLayout<simd_float3>.stride * 2 + MemoryLayout<UInt32>.stride

    var textureCache: CVMetalTextureCache?
    let metalDevice: MTLDevice
    let mpsScaleFilter: MPSImageBilinearScale?
    let commandQueue: MTLCommandQueue
    let YCbCrToRGBPipelineComputeState: MTLComputePipelineState?
    let RGBToMaskPipelineComputeState: MTLComputePipelineState?
    let RGBToLightSourceXYCoordsPipelineComputeState: MTLComputePipelineState?
    let LightSourceXYCoordsToWorldCoordsPipelineComputeState: MTLComputePipelineState?
    let LightSourceRGBToTexturePipelineComputeState: MTLComputePipelineState?
    let rayPipelineComputeState: MTLComputePipelineState?
    let intersectPipeline: MTLComputePipelineState?
    let addInsOutsPipeline: MTLComputePipelineState?
    let populateVoxelPipeline: MTLComputePipelineState?
    
    // Create an empty texture.
    static func createTexture(metalDevice: MTLDevice, width: Int, height: Int, usage: MTLTextureUsage, pixelFormat: MTLPixelFormat) -> MTLTexture {
        let descriptor: MTLTextureDescriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = usage
        let resTexture = metalDevice.makeTexture(descriptor: descriptor)
        return resTexture!
    }
    
    // Start or resume the stream from ARKit.
    func start() {
        arReceiver.start()
    }
    
    // Pause the stream from ARKit.
    func pause() {
        arReceiver.pause()
    }
    
    // Initialize the MPS filters, metal pipeline, and Metal textures.
    init() {
        do {
            vertCount = voxelsPerSide * voxelsPerSide * voxelsPerSide
            numVertices = vertCount * vertsPerVoxel
            numIndices = vertCount * indicesPerVoxel
            metalDevice = EnvironmentVariables.shared.metalDevice
            CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)
            mpsScaleFilter = MPSImageBilinearScale(device: metalDevice)
            commandQueue = EnvironmentVariables.shared.metalCommandQueue
            let lib = EnvironmentVariables.shared.metalLibrary
            let convertYUV2RGBFunc = lib.makeFunction(name: "convertYCbCrToRGBA")
            YCbCrToRGBPipelineComputeState = try metalDevice.makeComputePipelineState(function: convertYUV2RGBFunc!)
            let convertRGB2MaskFunc = lib.makeFunction(name: "getShadowMask")
            RGBToMaskPipelineComputeState = try metalDevice.makeComputePipelineState(function: convertRGB2MaskFunc!)
            let rayFuncDescriptor = MTLComputePipelineDescriptor()
            rayFuncDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
            rayFuncDescriptor.computeFunction = lib.makeFunction(name: "rayKernel")
            rayPipelineComputeState = try metalDevice.makeComputePipelineState(descriptor: rayFuncDescriptor,
                                                                   options: [],
                                                                         reflection: nil)
            let intersectDescriptor = MTLComputePipelineDescriptor()
            intersectDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
            intersectDescriptor.computeFunction = lib.makeFunction(name: "intersect")
            intersectPipeline = try metalDevice.makeComputePipelineState(descriptor: intersectDescriptor,
                                                                   options: [],
                                                                         reflection: nil)
            let addInsOutDescriptor = MTLComputePipelineDescriptor()
            addInsOutDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
            addInsOutDescriptor.computeFunction = lib.makeFunction(name: "addInsOuts")
            addInsOutsPipeline = try metalDevice.makeComputePipelineState(descriptor: addInsOutDescriptor,
                                                                         options: [],
                                                                               reflection: nil)
                  
            let populateVoxelDesc = MTLComputePipelineDescriptor()
            populateVoxelDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
            populateVoxelDesc.computeFunction = lib.makeFunction(name: "samplePopulateVoxels")
            populateVoxelPipeline = try metalDevice.makeComputePipelineState(descriptor: populateVoxelDesc,
                                                                   options: [],
                                                                         reflection: nil)
            let convertRGB2LightSourceCoordsFunc = lib.makeFunction(name: "getLightSource")
            RGBToLightSourceXYCoordsPipelineComputeState = try metalDevice.makeComputePipelineState(function: convertRGB2LightSourceCoordsFunc!)
            let convertRGB2LightSourceTexture = lib.makeFunction(name: "getLightSourceTexture")
            LightSourceRGBToTexturePipelineComputeState = try metalDevice.makeComputePipelineState(function: convertRGB2LightSourceTexture!)
            let convertLightSourceCoords2WorldCoordsFunc = lib.makeFunction(name: "getWorldCoords")
            LightSourceXYCoordsToWorldCoordsPipelineComputeState = try metalDevice.makeComputePipelineState(function: convertLightSourceCoords2WorldCoordsFunc!)
            // Initialize the working textures.
            maskTexture = ARProvider.createTexture(metalDevice: metalDevice, width: origColorWidth, height: origColorHeight,
                                                                                         usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            maskTextureDownscaled = ARProvider.createTexture(metalDevice: metalDevice, width: origDepthWidth, height: origDepthHeight,
                                                                                         usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            coefTexture = ARProvider.createTexture(metalDevice: metalDevice, width: origDepthWidth, height: origDepthHeight,
                                                   usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            destDepthTexture = ARProvider.createTexture(metalDevice: metalDevice, width: upscaledWidth, height: upscaledHeight,
                                                        usage: [.shaderRead, .shaderWrite], pixelFormat: .r32Float)
            destConfTexture = ARProvider.createTexture(metalDevice: metalDevice, width: upscaledWidth, height: upscaledHeight,
                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .r8Unorm)
            colorRGBTexture = ARProvider.createTexture(metalDevice: metalDevice, width: origColorWidth, height: origColorHeight,
                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            colorRGBMaskedTexture = ARProvider.createTexture(metalDevice: metalDevice, width: origColorWidth, height: origColorHeight,
                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)

            colorRGBTextureDownscaled = ARProvider.createTexture(metalDevice: metalDevice, width: upscaledWidth, height: upscaledHeight,
                                                                 usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            colorRGBTextureDownscaledLowRes = ARProvider.createTexture(metalDevice: metalDevice, width: origDepthWidth, height: origDepthHeight,
                                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            colorRGBTextureBlurred = ARProvider.createTexture(metalDevice: metalDevice, width: origColorWidth, height: origColorHeight,
                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            colorRGBTextureBlurredDownscaled = ARProvider.createTexture(metalDevice: metalDevice, width: origDepthWidth, height: origDepthHeight,
                                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            upscaledCoef.texture = coefTexture
            upscaledConfidence.texture = destConfTexture
            downscaledRGB.texture = colorRGBTextureDownscaled
            colorRGB.texture = colorRGBTexture
            colorRGBMasked.texture = colorRGBMaskedTexture
            voxelIns = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size * voxelsPerSide * voxelsPerSide * voxelsPerSide)!
            voxelOuts = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size * voxelsPerSide * voxelsPerSide * voxelsPerSide)!
            voxelInsTemp = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size * voxelsPerSide * voxelsPerSide * voxelsPerSide)!
            voxelOutsTemp = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size * voxelsPerSide * voxelsPerSide * voxelsPerSide)!
//
//            let w: Float32 = 0.05
//            let h: Float32 = 0.05
//            let l: Float32 = 0.05
//            let verts: [simd_float3] = [
//                // bottom 4 vertices
//                simd_float3(-w, -h, -l),
//                simd_float3(w, -h, -l),
//                simd_float3(w, -h, l),
//                simd_float3(-w, -h, l),
//
//                // top 4 vertices
//                simd_float3(-w, h, -l),
//                simd_float3(w, h, -l),
//                simd_float3(w, h, l),
//                simd_float3(-w, h, l),
//            ]
//            var indices: [UInt32] = [
//                // bottom face
//                0, 1, 3,
//                3, 1, 2,
//                // left face
//                0, 3, 4,
//                4, 3, 7,
//                // right face
//                1, 5, 2,
//                2, 5, 6,
//                // top face
//                4, 7, 5,
//                5, 7, 6,
//                // front face
//                3, 2, 7,
//                7, 2, 6,
//                // back face
//                0, 4, 1,
//                1, 4, 5,
//            ]
            blurKernel = MPSImageGaussianBlur(device: metalDevice, sigma: blurSigma)
            vertBuffer = metalDevice.makeBuffer(length: MemoryLayout<simd_float3>.stride * numVertices)!
            indBuffer = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.stride * numIndices)!
            // Set the delegate for ARKit callbacks.
            arReceiver.delegate = self
            
        } catch {
            fatalError("Unexpected error: \(error).")
        }
    }
    
    func populateVoxels() {
        // populate voxels
        let occupancies = metalDevice.makeBuffer(length: MemoryLayout<simd_float3>.stride * voxelsPerSide * voxelsPerSide * voxelsPerSide, options: [])!
        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
        computeEncoder.setComputePipelineState(populateVoxelPipeline!)
        let threadgroupSize = MTLSizeMake(16, 16, 1)
        let threadgroupCount = MTLSize(width: Int(ceil(Float(voxelsPerSide) / Float(threadgroupSize.width))),
                                       height: Int(ceil(Float(voxelsPerSide) / Float(threadgroupSize.height))), depth: voxelsPerSide)
        computeEncoder.setBuffer(vertBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(indBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(voxelIns, offset: 0, index: 2)
        computeEncoder.setBuffer(voxelOuts, offset: 0, index: 3)
        computeEncoder.setBuffer(occupancies, offset: 0, index: 4)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        var count = 0
//            for i in 0..<(self.voxelsPerSide*self.voxelsPerSide*self.voxelsPerSide) {
//                let occupPointer = occupancies.contents().advanced(by: (MemoryLayout<simd_float3>.stride * Int(i)))
//                let occupancy = occupPointer.assumingMemoryBound(to: simd_float3.self).pointee
//                if /*occupancy[0] > 0.4 &&*/ occupancy[2] > 0 {
//                    print("I: " + String(i))
//                    print(occupancy)
//                }
//            }
//        print("count")
//        print(count)
//        let worldCoords = floatBuff.contents().load(as: simd_float3.self)
//        print("wc")
//        print(worldCoords)
    }
    
    func rayTraceLastFrame() {
        //print(origDepthWidth, origDepthHei ght)
        var cameraIntrinsics = ShadowMasks.last!.cameraIntrinsics
        var lastWorldCoords = LightSources.last!.worldCoords
        let scaleRes = simd_float2(x: Float(lastArData!.cameraResolution.width) / Float(origDepthWidth),
                                   y: Float(lastArData!.cameraResolution.height) / Float(origDepthHeight))
        cameraIntrinsics[0][0] /= scaleRes.x
        cameraIntrinsics[1][1] /= scaleRes.y

        cameraIntrinsics[2][0] /= scaleRes.x
        cameraIntrinsics[2][1] /= scaleRes.y
//        print("intr")
//        print(cameraIntrinsics)
        
        // create intersector/acceleration structure
        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }

        let rayBuffer = metalDevice.makeBuffer(length: rayStride * origDepthWidth * origDepthHeight, options: .storageModeShared) // maybe can be private storage
        
        var threadsPerThreadgroup = MTLSizeMake(16, 16, 1)
        var threadsHeight = threadsPerThreadgroup.height
        var threadsWidth = threadsPerThreadgroup.width
        var threadgroups = MTLSizeMake((origDepthWidth + threadsWidth  - 1) / threadsWidth, (origDepthHeight + threadsHeight  - 1) / threadsHeight, 1)

        // debug, look at ray data
        var origin = LightSources.last!.worldCoords
        let originBuff = metalDevice.makeBuffer(bytes: &origin, length: MemoryLayout<simd_float3>.size, options: [])!
        let rayOrig = metalDevice.makeBuffer(length: MemoryLayout<simd_float3>.size, options: [])!
        let rayDir = metalDevice.makeBuffer(length: MemoryLayout<simd_float3>.size, options: [])!
        let rayCount = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size, options: [])!
        let rayOutCount = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size, options: [])!

        computeEncoder.setTexture(ShadowMasks.last!.depthTexture, index: 0)
        computeEncoder.setTexture(ShadowMasks.last!.mask.texture, index: 1)
        computeEncoder.setBuffer(rayBuffer, offset: 0, index: 0)
        computeEncoder.setBytes(&lastWorldCoords, length: MemoryLayout<simd_float3>.stride, index: 1)
        computeEncoder.setBytes(&cameraIntrinsics, length: MemoryLayout<matrix_float3x3>.stride, index: 2)
        computeEncoder.setBuffer(rayOrig, offset: 0, index: 3)
        computeEncoder.setBuffer(rayDir, offset: 0, index: 4)
        computeEncoder.setBuffer(rayCount, offset: 0, index: 5)
        computeEncoder.setBuffer(rayOutCount, offset: 0, index: 6)
        computeEncoder.setComputePipelineState(rayPipelineComputeState!)
        // Launch threads
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        // End the encoder
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        print("origin, dir")
        print(rayOrig.contents().load(as: simd_float3.self))
        print(rayDir.contents().load(as: simd_float3.self))
        print("ray in count")
        print(rayCount.contents().load(as: UInt32.self))
        print("ray out count")
        print(rayOutCount.contents().load(as: UInt32.self))
        print((Int(xMax/7.5) - Int(xMin/7.5)) * (Int(yMax/7.5) - Int(yMin/7.5)))

        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
        
        threadsPerThreadgroup = MTLSizeMake(16, 16, 1)
        threadsHeight = threadsPerThreadgroup.height
        threadsWidth = threadsPerThreadgroup.width
        threadgroups = MTLSizeMake((origDepthWidth + threadsWidth  - 1) / threadsWidth, (origDepthHeight + threadsHeight  - 1) / threadsHeight, 1)

        // debug, look at ray data
        computeEncoder.setBuffer(rayBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(voxelInsTemp, offset: 0, index: 1)
        computeEncoder.setBuffer(voxelOutsTemp, offset: 0, index: 2)
        computeEncoder.setBytes(&origDepthWidth, length: MemoryLayout<UInt32>.stride, index: 3)
        computeEncoder.setComputePipelineState(intersectPipeline!)
        // Launch threads
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        // End the encoder
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
//        for i in 0..<(voxelsPerSide*voxelsPerSide*voxelsPerSide) {
//            let vertexPointer = voxelInsTemp.contents().advanced(by: (MemoryLayout<UInt32>.stride * Int(i)))
//            let vert = vertexPointer.assumingMemoryBound(to: UInt32.self).pointee
//            let vertexPointerT = voxelOutsTemp.contents().advanced(by: (MemoryLayout<UInt32>.stride * Int(i)))
//            let vertT = vertexPointerT.assumingMemoryBound(to: UInt32.self).pointee
//            if vert != 0 || vertT != 0 {
//                print("I: " + String(i))
//                print(vertexPointer.assumingMemoryBound(to: UInt32.self).pointee)
//                print(vertT)
//            }
//        }
        // do m + n count
        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
        
        threadsPerThreadgroup = MTLSizeMake(16, 16, 1)
        threadsHeight = threadsPerThreadgroup.height
        threadsWidth = threadsPerThreadgroup.width
        threadgroups = MTLSize(width: Int(ceil(Float(voxelsPerSide) / Float(threadsPerThreadgroup.width))),
                               height: Int(ceil(Float(voxelsPerSide) / Float(threadsPerThreadgroup.height))), depth: voxelsPerSide)

        // debug, look at ray data
        computeEncoder.setBuffer(voxelInsTemp, offset: 0, index: 0)
        computeEncoder.setBuffer(voxelOutsTemp, offset: 0, index: 1)
        computeEncoder.setBuffer(voxelIns, offset: 0, index: 2)
        computeEncoder.setBuffer(voxelOuts, offset: 0, index: 3)
        computeEncoder.setComputePipelineState(addInsOutsPipeline!)
        // Launch threads
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        // End the encoder
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        print("done")
        //LightSources.removeLast()
        //ShadowMasks.removeLast()
        print("removed shadows and light source")
        
    }
    // Save a reference to the current AR data and process it.
    func onNewARData(arData: ARData) {
        lastArData = arData
        processLastArData()
    }
    func deleteFrameAtIndex(index: Int) {
        ShadowMasks.remove(at:index)
        
        LightSources.remove(at:index)
        framesCaptured = framesCaptured - 1
    }
    // Copy the AR data to Metal textures and, if the user enables the UI, upscale the depth using a guided filter.
    func processLastArData() {
        colorYContent.texture = lastArData?.colorImage?.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache!)!
        colorCbCrContent.texture = lastArData?.colorImage?.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache!)!
        if isUseSmoothedDepthForUpsampling {
            depthContent.texture = lastArData?.depthSmoothImage?.texture(withFormat: .r32Float, planeIndex: 0, addToCache: textureCache!)!
            confidenceContent.texture = lastArData?.confidenceSmoothImage?.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache!)!
        } else {
            depthContent.texture = lastArData?.depthImage?.texture(withFormat: .r32Float, planeIndex: 0, addToCache: textureCache!)!
            confidenceContent.texture = lastArData?.confidenceImage?.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache!)!
        }
        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
        // Convert YUV to RGB because the guided filter needs RGB format.
        computeEncoder.setComputePipelineState(YCbCrToRGBPipelineComputeState!)
        computeEncoder.setTexture(colorYContent.texture, index: 0)
        computeEncoder.setTexture(colorCbCrContent.texture, index: 1)
        computeEncoder.setTexture(colorRGBTexture, index: 2)
        let threadgroupSize = MTLSizeMake(YCbCrToRGBPipelineComputeState!.threadExecutionWidth,
                                          YCbCrToRGBPipelineComputeState!.maxTotalThreadsPerThreadgroup / YCbCrToRGBPipelineComputeState!.threadExecutionWidth, 1)
        let threadgroupCount = MTLSize(width: Int(ceil(Float(colorRGBTexture.width) / Float(threadgroupSize.width))),
                                       height: Int(ceil(Float(colorRGBTexture.height) / Float(threadgroupSize.height))),
                                       depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        cmdBuffer.commit()
        if /*calibrateMask*/ true {
            blurKernel = MPSImageGaussianBlur(device: metalDevice, sigma: blurSigma)
            guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
            blurKernel.encode(commandBuffer: cmdBuffer,
                          sourceTexture: colorRGBTexture,
                          destinationTexture: colorRGBTextureBlurred)
            var xMinInt = UInt32(xMin)
            var xMaxInt = UInt32(xMax)
            var yMinInt = UInt32(yMin)
            var yMaxInt = UInt32(yMax)
            var sideLenInt = UInt32(sideLen)
            guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
            computeEncoder.setComputePipelineState(RGBToMaskPipelineComputeState!)
            computeEncoder.setTexture(colorRGBTextureBlurred, index: 0)
            computeEncoder.setTexture(colorRGBMaskedTexture, index: 1)
            computeEncoder.setBytes(&minGray, length: MemoryLayout<simd_float1>.stride, index: 0)
            computeEncoder.setBytes(&maxGray, length: MemoryLayout<simd_float1>.stride, index: 1)
            computeEncoder.setBytes(&xMinInt, length: MemoryLayout<UInt32>.stride, index: 2)
            computeEncoder.setBytes(&xMaxInt, length: MemoryLayout<UInt32>.stride, index: 3)
            computeEncoder.setBytes(&yMinInt, length: MemoryLayout<UInt32>.stride, index: 4)
            computeEncoder.setBytes(&yMaxInt, length: MemoryLayout<UInt32>.stride, index: 5)
            computeEncoder.setBytes(&sideLenInt, length: MemoryLayout<UInt32>.stride, index: 6)
            computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            computeEncoder.endEncoding()
            cmdBuffer.commit()
            if calibrateMask {
                print("mask params")
                print(minGray)
                print(maxGray)
                print(xMinInt)
                print(xMaxInt)
                print(yMinInt)
                print(yMaxInt)
                print(sideLenInt)
            }
        }
        // maybe don't need these lines
        colorRGB.texture = colorRGBTexture
        colorRGBMasked.texture = colorRGBMaskedTexture
    }

    // workaround to perms errors in MetalViewSample
    func switchMaskSides() {
        if xMin == xMinL {
            xMin = xMinR
            xMax = xMaxR
            yMin = yMinR
            yMax = yMaxR
            sideLen = sideLenR
        } else {
            xMin = xMinL
            xMax = xMaxL
            yMin = yMinL
            yMax = yMaxL
            sideLen = sideLenL
        }
    }
    // workaround to perms errors in MetalViewSample
    func toggleCalibrateMask() {
        calibrateMask = !calibrateMask
    }
    
    func setGrayscaleMin(minGrayVal: simd_float1) {
        minGray = minGrayVal
    }
    
    func setGrayscaleMax(maxGrayVal: simd_float1) {
        maxGray = maxGrayVal
    }

}

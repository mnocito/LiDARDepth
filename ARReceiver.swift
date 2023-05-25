/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A utility class that receives processed depth information.
*/

import Foundation
import SwiftUI
import Combine
import ARKit

// Receive the newest AR data from an `ARReceiver`.
protocol ARDataReceiver: AnyObject {
    func onNewARData(arData: ARData)
}

//- Tag: ARData
// Store depth-related AR data.
final class ARData {
    var depthImage: CVPixelBuffer?
    var depthSmoothImage: CVPixelBuffer?
    var colorImage: CVPixelBuffer?
    var confidenceImage: CVPixelBuffer?
    var confidenceSmoothImage: CVPixelBuffer?
    var cameraIntrinsics = simd_float3x3()
    var cameraResolution = CGSize()
}

// Configure and run an AR session to provide the app with depth-related AR data.
final class ARReceiver: NSObject, ARSessionDelegate {
    var arData = ARData()
    var arSession = ARSession()
    weak var delegate: ARDataReceiver?
    var isReconstructing = false
    
    // Configure and start the ARSession.
    override init() {
        super.init()
        arSession.delegate = self
        start()
        let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)! // unsafe if running on non-lidar available device
        guard let format = (device.formats.last { format in
            format.formatDescription.dimensions.width == 1920 &&
            format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
            !format.isVideoBinned &&
            !format.supportedDepthDataFormats.isEmpty
        }) else {
            print("no")
            return
        }
        
        guard let depthFormat = (format.supportedDepthDataFormats.last { depthFormat in
            depthFormat.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
        }) else {
            print("nope")
            return
        }
        // Begin the device configuration.
        do {
            try device.lockForConfiguration()
        } catch {
            // Configure the device and depth formats.
            device.activeFormat = format
            device.exposureMode = AVCaptureDevice.ExposureMode.custom;
            // magic apple constants
            //let shortTime = CMTimeMake(value: 1, timescale: 100) // good for low exp
            //device.setExposureModeCustom(duration: shortTime, iso: 300, completionHandler: nil)
            let longTime = CMTimeMake(value: 33210999, timescale: 1000000000)
            device.setExposureModeCustom(duration: longTime, iso: 1728, completionHandler: nil)
            device.activeDepthDataFormat = depthFormat

            // Finish the device configuration.
            device.unlockForConfiguration()
        }
    }
    
    // Configure the ARKit session.
    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) else { return }
        // Enable both the `sceneDepth` and `smoothedSceneDepth` frame semantics.
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        config.sceneReconstruction = .mesh
        arSession.run(config)
    }
    
    func pause() {
        arSession.pause()
    }
  
    // Send required data from `ARFrame` to the delegate class via the `onNewARData` callback.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if(frame.sceneDepth != nil) && (frame.smoothedSceneDepth != nil) {
            isReconstructing = true
            arData.depthImage = frame.smoothedSceneDepth?.depthMap//frame.sceneDepth?.depthMap
            arData.depthSmoothImage = frame.smoothedSceneDepth?.depthMap
            arData.confidenceImage = frame.sceneDepth?.confidenceMap
            arData.confidenceSmoothImage = frame.smoothedSceneDepth?.confidenceMap
            arData.colorImage = frame.capturedImage
            arData.cameraIntrinsics = frame.camera.intrinsics
            arData.cameraResolution = frame.camera.imageResolution
            delegate?.onNewARData(arData: arData)
            
        }
    }
}

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
    var anchors = [ARMeshAnchor]()
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
            let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            if anchors.count > 0 {
                if !isReconstructing {
                    isReconstructing = true
                    print("Reconstructing scene")
                }
            } else {
                if isReconstructing {
                    isReconstructing = false
                    print("No longer reconstructing scene")
                }
            }
            arData.anchors = anchors
            arData.depthImage = frame.sceneDepth?.depthMap
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

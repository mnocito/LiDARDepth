//
//  MetalStructs.swift
//  LiDARDepth
//
//  Created by Marco Nocito on 3/13/23.
//  Copyright © 2023 Apple. All rights reserved.
//

import Foundation
import simd
import Metal

struct LightSource {
    var texture: MetalTextureContent
    var worldCoords: SIMD3<Float>
}

struct ShadowMask {
    var mask: MetalTextureContent
    var depthTexture: MTLTexture
    var cameraIntrinsics: matrix_float3x3
}

struct Voxel {
    var worldCoords: SIMD3<Float>
    var ins: UInt32
    var outs: UInt32
}

import SwiftUI
import SceneKit
import ARKit

struct DisplayObjectView : UIViewRepresentable {
    let scene = SCNScene()
    var arSession: ARSession!
    var vertBuffer: MTLBuffer!
    var indBuffer: MTLBuffer!
    let vertCount = 30 * 30 * 30 // TODO: not make magic number later
    let vertsPerVoxel = 8
    let indicesPerVoxel = 36
    let numVerts: Int!
    let numIndices: Int!
    
    init(session: ARSession!, vBuffer: MTLBuffer!, iBuffer: MTLBuffer!) {
        arSession = session
        vertBuffer = vBuffer
        indBuffer = iBuffer
        numVerts = vertCount * vertsPerVoxel
        numIndices = vertCount * indicesPerVoxel
    }

    func makeUIView(context: Context) -> SCNView {

        // create and add a light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 3, z: 3)
        scene.rootNode.addChildNode(lightNode)

        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)

//        let w: Float32 = 0.05
//        let h: Float32 = 0.05
//        let l: Float32 = 0.05
//        let verts: [simd_float3] = [
//            // bottom 4 vertices
//            simd_float3(-w, -h, -l),
//            simd_float3(w, -h, -l),
//            simd_float3(w, -h, l),
//            simd_float3(-w, -h, l),
//
//            // top 4 vertices
//            simd_float3(-w, h, -l),
//            simd_float3(w, h, -l),
//            simd_float3(w, h, l),
//            simd_float3(-w, h, l),
//        ]
//        var indices: [UInt32] = [
//            // bottom face
//            0, 1, 3,
//            3, 1, 2,
//            // left face
//            0, 3, 4,
//            4, 3, 7,
//            // right face
//            1, 5, 2,
//            2, 5, 6,
//            // top face
//            4, 7, 5,
//            5, 7, 6,
//            // front face
//            3, 2, 7,
//            7, 2, 6,
//            // back face
//            0, 4, 1,
//            1, 4, 5,
//        ]
//        let vertexDataOriginal = Data(
//            bytes: verts,
//            count: MemoryLayout<simd_float3>.size * verts.count
//        )
//        let verticesBuff = EnvironmentVariables.shared.metalDevice.makeBuffer(bytes: verts, length: MemoryLayout<simd_float3>.stride * verts.count)
//        let indicesBuff = EnvironmentVariables.shared.metalDevice.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count)
        let vertexData = Data(
            bytes: UnsafeRawPointer(vertBuffer.contents()),
            count: MemoryLayout<SIMD3<Float>>.stride * numVerts
        )
        let indexData = Data(
            bytes: UnsafeRawPointer(indBuffer.contents()),
            count: MemoryLayout<UInt32>.size * numIndices
        )
        let positionSource = SCNGeometrySource(
            data: vertexData,
            semantic: SCNGeometrySource.Semantic.vertex,
            vectorCount: numVerts,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<simd_float3>.size
        )
        
        let elements = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: numIndices / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry.init(sources: [positionSource], elements: [elements])
        
        //geometry.firstMaterial?.diffuse.contents = UIColor.red
        //let geometry = SCNBox(width: 0.25, height: 0.25, length: 0.25, chamferRadius: 0)
        geometry.firstMaterial?.diffuse.contents = UIColor.white
        geometry.firstMaterial?.specular.contents = UIColor(white: 0.6, alpha: 1.0)
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(x: 0, y: 0, z: -0.25)
        scene.rootNode.addChildNode(node)
        for i in 0..<(30*30*30) {
            let vertexPointer = vertBuffer.contents().advanced(by: (MemoryLayout<simd_float3>.stride * Int(i)))
            let vert = vertexPointer.assumingMemoryBound(to: simd_float3.self).pointee
            if vert[0] != 0 || vert[1] != 0 || vert[2] != 0 {
                print("I: " + String(i))
                print(vert)
            }
        }

        // retrieve the ship node
        //let ship = scene.rootNode.childNode(withName: "ship", recursively: true)!
        //ship.position = SCNVector3(x: 0, y: 0, z: -10)
        
//        // retrieve the SCNView
//        let boxGeometry = SCNBox(width: 0.01, height: 0.01, length: 0.01, chamferRadius: 0)
//        //let boxGeometry2 = SCNBox(width: 0.01, height: 0.01, length: 0.01, chamferRadius: 0)
//
//        let material = SCNMaterial()
//
//        material.diffuse.contents = UIColor.white
//        material.specular.contents = UIColor(white: 0.6, alpha: 1.0)
//
//        let boxNode = SCNNode(geometry: boxGeometry)
//        boxNode.geometry?.materials = [material]
//        let boxNode2 = SCNNode(geometry: boxGeometry)
//        boxNode2.geometry?.materials = [material]
//        for i in 0..<20 {
//            for j in 0..<20 {
//                for k in 0..<20 {
//                    let boxNode = SCNNode(geometry: boxGeometry)
//                    boxNode.geometry?.materials = [material]
//                    if i == 5 {
//                        continue
//                    }
//                    boxNode.position = SCNVector3(-0.05 + Double(i) * 0.01,-0.05 + Double(j) * 0.01,-1.05 + Double(k) * 0.01)
//                    scene.rootNode.addChildNode(boxNode)
//                }
//            }
//        }
        let scnView = ARSCNView()
        scnView.session = arSession
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.scene = scene

        // show statistics such as fps and timing information
        scnView.showsStatistics = true
        
        scnView.autoenablesDefaultLighting = true

        // configure the view
        scnView.backgroundColor = UIColor.black
    }
}

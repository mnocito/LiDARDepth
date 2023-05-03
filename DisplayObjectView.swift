import SwiftUI
import SceneKit
import ARKit

struct DisplayObjectView : UIViewRepresentable {
    let scene = SCNScene()
    var arSession: ARSession!
    //var objectBuffer: MTLBuffer!
    
    init(session: ARSession!) {
        arSession = session
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
        
        let w = 0.1
        let h = 0.1
        let l = 0.1
        let verts = [
            // bottom 4 vertices
            SCNVector3(-w, -h, -l),
            SCNVector3(w, -h, -l),
            SCNVector3(w, -h, l),
            SCNVector3(-w, -h, l),

            // top 4 vertices
            SCNVector3(-w, h, -l),
            SCNVector3(w, h, -l),
            SCNVector3(w, h, l),
            SCNVector3(-w, h, l),
        ]
        var indices: [UInt32] = [
            // bottom face
            0, 1, 3,
            3, 1, 2,
            // left face
            0, 3, 4,
            4, 3, 7,
            // right face
            1, 5, 2,
            2, 5, 6,
            // top face
            4, 7, 5,
            5, 7, 6,
            // front face
            3, 2, 7,
            7, 2, 6,
            // back face
            0, 4, 1,
            1, 4, 5,
        ]
        let vertexData = Data(
            bytes: verts,
            count: MemoryLayout<SCNVector3>.size * verts.count
        )
        let indexData = Data(
            bytes: indices,
            count: MemoryLayout<UInt32>.size * indices.count
        )
        
        let positionSource = SCNGeometrySource(
            data: vertexData,
            semantic: SCNGeometrySource.Semantic.vertex,
            vectorCount: verts.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        let elements = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry.init(sources: [positionSource], elements: [elements])
        //geometry.firstMaterial?.diffuse.contents = UIColor.red
        //let geometry = SCNBox(width: 0.25, height: 0.25, length: 0.25, chamferRadius: 0)
        geometry.firstMaterial?.diffuse.contents = UIColor.white
        geometry.firstMaterial?.specular.contents = UIColor(white: 0.6, alpha: 1.0)
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(x: 0, y: 0, z: -1)
        scene.rootNode.addChildNode(node)

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

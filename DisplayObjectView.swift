import SwiftUI
import SceneKit
import ARKit

struct DisplayObjectView : UIViewRepresentable {
    let scene = SCNScene(named: "ship.scn")!
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
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        scene.rootNode.addChildNode(lightNode)

        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)

        // retrieve the ship node
        let ship = scene.rootNode.childNode(withName: "ship", recursively: true)!
        ship.position = SCNVector3(x: 0, y: 0, z: -10)
        
        // retrieve the SCNView
        let scnView = ARSCNView()
        scnView.session = arSession
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.scene = scene

        // show statistics such as fps and timing information
        scnView.showsStatistics = true

        // configure the view
        scnView.backgroundColor = UIColor.black
    }
}

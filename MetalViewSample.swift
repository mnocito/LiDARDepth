/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A parent view class that displays the sample app's other views.
*/

import Foundation
import SwiftUI
import MetalKit
import ARKit
import SceneKit

// Add a title to a view that enlarges the view to full screen on tap.
struct Texture<T: View>: ViewModifier {
    let height: CGFloat
    let width: CGFloat
    let title: String
    let view: T
    func body(content: Content) -> some View {
        VStack {
            Text(title).foregroundColor(Color.red)
            // To display the same view in the navigation, reference the view
            // directly versus using the view's `content` property.
            NavigationLink(destination: view.aspectRatio(CGSize(width: width, height: height), contentMode: .fill)) {
                view.frame(maxWidth: width, maxHeight: height, alignment: .center)
                    .aspectRatio(CGSize(width: width, height: height), contentMode: .fill)
            }
        }
    }
}

extension View {
    // Apply `zoomOnTapModifier` with a `self` reference to show the same view
    // on tap.
    func zoomOnTapModifier(height: CGFloat, width: CGFloat, title: String) -> some View {
        modifier(Texture(height: height, width: width, title: title, view: self))
    }
}
extension Image {
    init(_ texture: MTLTexture, ciContext: CIContext, scale: CGFloat, orientation: Image.Orientation, label: Text) {
        let ciimage = CIImage(mtlTexture: texture)!
        let cgimage = ciContext.createCGImage(ciimage, from: ciimage.extent)
        // try right orientation
        self.init(cgimage!, scale: 1, orientation: orientation, label: label)
    }
}


//- Tag: MetalDepthView
struct MetalDepthView: View {
    
    // Set the default sizes for the texture views.
    let sizeH: CGFloat = 704
    let sizeW: CGFloat = 528
    
    // Manage the AR session and AR data processing.
    //- Tag: ARProvider
    @State var arProvider: ARProvider = ARProvider()
    let ciContext: CIContext = CIContext()
    
    // Save the user's confidence selection.
    @State private var selectedConfidence = 0
    // Set the depth view's state data.
    @State var framesCaptured = 0
    @State var isToUpsampleDepth = false
    @State var isShowSmoothDepth = false
    @State var isArPaused = false
    @State var chooseFrames = false
    @State var showObject = false
    @State var calibrateMask = false
    @State private var scaleMovement: Float = 1.5
    
    var confLevels = ["🔵🟢🔴", "🔵🟢", "🔵"]
    
    
    var body: some View {
        //SceneView(scene: SCNScene(named: "ship.scn"), options: [.allowsCameraControl,.autoenablesDefaultLighting]).frame(width: 500)
        if !ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            Text("Unsupported Device: This app requires the LiDAR Scanner to access the scene's depth.")
        } else {
            if !chooseFrames && !showObject && !calibrateMask {
                NavigationView{
                        VStack() {
                            HStack() {
                                Spacer()
                                MetalTextureRGBImage(content: arProvider.colorRGB)
                                    //.zoomOnTapModifier(height: sizeH, width: sizeW, title: "")
                                    .aspectRatio(CGSize(width: sizeW, height: sizeH), contentMode: .fit)
                                    .rotationEffect(.degrees(-90))
                                Spacer()
                            }
                            HStack {
                                Text("Frames captured: \(framesCaptured)")
                                Button(action: {
                                                do {
                                                    try arProvider.captureFrame()
                                                } catch IBOError.lightSourceNotFound {
                                                    print("Can't find light source, skipping frame")
                                                    framesCaptured = framesCaptured - 1
                                                } catch IBOError.ARKitNotReconstructing {
                                                    print("ARKit not currently reconstructing scene, skipping frame")
                                                    framesCaptured = framesCaptured - 1
                                                } catch {
                                                    // shouldn't happen
                                                }
                                                framesCaptured += 1
                                            }) {
                                                Text("Capture Frame")
                                            }.buttonStyle(.bordered)
                                Button(action: {
                                                chooseFrames = true
                                            }) {
                                                Text("Manage captured frames")
                                            }.buttonStyle(.bordered)
                                Button(action: {
                                                arProvider.populateVoxels()
                                                showObject = true
                                            }) {
                                                Text("Carve chosen frames")
                                            }.buttonStyle(.bordered)
                                Button(action: {
                                                //arProvider.populateVoxels()
                                                calibrateMask = true
                                                arProvider.toggleCalibrateMask()
                                            }) {
                                                Text("Calibrate mask")
                                            }.buttonStyle(.bordered)
                            }.padding(.horizontal)
                        }
                    }.navigationViewStyle(StackNavigationViewStyle())
            } else if showObject {
                Button(action: {
                                showObject = false
                            }) {
                                Text("Back")
                            }.buttonStyle(.bordered)
                DisplayObjectView(session: arProvider.arReceiver.arSession, vBuffer: arProvider.vertBuffer, iBuffer: arProvider.indBuffer, numVerts: arProvider.numVertices, numInds: arProvider.numIndices)
            } else if calibrateMask {
                Button(action: {
                                calibrateMask = false
                                arProvider.toggleCalibrateMask()
                            }) {
                                Text("Back")
                            }.buttonStyle(.bordered)
                MetalTextureCalibrateMask(content: arProvider.colorRGBMasked)
                    .zoomOnTapModifier(height: CGFloat(floor(sizeH/1.2)), width: CGFloat(floor(sizeW/1.2)), title: "")
                    .rotationEffect(.degrees(-90))
                HStack {
                    Text("Min gray value")
                    Slider(value: $arProvider.minGray, in: 0...1, step: 0.0001)
                    Text("Max gray value")
                    Slider(value: $arProvider.maxGray, in: 0...1, step: 0.0001)
                    Text("Blur sigma")
                    Slider(value: $arProvider.blurSigma, in: 0...12, step: 0.1)
                    //Text(String(format: "%.3f", arProvider.minGray))
                }.padding(.horizontal)
                
            } else {
                VStack {
                    Button(action: {
                                    chooseFrames = false
                                }) {
                                    Text("Back")
                    }.buttonStyle(.bordered)
                    ScrollView {    
                        ForEach(0..<framesCaptured, id: \.self) { (index) in
                            HStack{
                                Text("\(index+1)")
                                Spacer().frame(width: 50)
                                MetalTextureRGBImage(content: arProvider.LightSources[index].texture)
                                    .zoomOnTapModifier(height: CGFloat(floor(sizeH/2.5)), width: CGFloat(floor(sizeW/2.5)), title: "")
                                    .rotationEffect(.degrees(-90))
                                Spacer().frame(width: 50)
                                MetalTextureRGBImage(content: arProvider.ShadowMasks[index].mask)
                                    .zoomOnTapModifier(height: CGFloat(floor(sizeH/2.5)), width: CGFloat(floor(sizeW/2.5)) , title: "")
                                    .rotationEffect(.degrees(-90))
                                Spacer().frame(width: 50)
                                Button(action: {
                                                arProvider.deleteFrameAtIndex(index: index)
                                                framesCaptured = framesCaptured - 1
                                            }) {
                                                Text("Delete frame")
                                }.buttonStyle(.bordered)
                                
                            }.id(UUID()) // UUID makes the view refresh on each delete
                        }
                    }.frame(width: 1600)
                }.padding(.horizontal)
            }
        }
    }
}
struct MtkView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MetalDepthView().previewDevice("iPad Pro (12.9-inch) (4th generation)")
            MetalDepthView().previewDevice("iPhone 11 Pro")
        }
    }
}

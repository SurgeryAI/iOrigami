import SwiftUI
import SceneKit

struct SceneKitView: UIViewRepresentable {
    @ObservedObject var engine: OrigamiEngine
    @Binding var dragStart: CGPoint?
    @Binding var dragEnd: CGPoint?
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = engine.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(pan)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: SceneKitView
        init(_ parent: SceneKitView) { self.parent = parent }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            switch gesture.state {
            case .began:
                // Disable camera control so we don't spin while folding
                scnView.allowsCameraControl = false
                parent.dragStart = location
                parent.dragEnd = location
            case .changed:
                parent.dragEnd = location
            case .ended:
                if let start = parent.dragStart {
                    // Start the folding animation
                    parent.engine.processFold(from: start, to: location, in: scnView)
                }
                parent.dragStart = nil
                parent.dragEnd = nil
                // Re-enable camera so the user can admire their work
                scnView.allowsCameraControl = true
            default:
                break
            }
        }
    }
}

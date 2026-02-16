import SwiftUI
import SceneKit

struct SceneKitView: UIViewRepresentable {
    @ObservedObject var engine: OrigamiEngine
    @Binding var dragStart: CGPoint?
    @Binding var dragEnd: CGPoint?
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = engine.scene
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        
        // Disable built-in controls to prevent conflict
        scnView.allowsCameraControl = false
        
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        scnView.addGestureRecognizer(pan)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject {
        var parent: SceneKitView
        var lastFingerPosition: CGPoint?

        init(_ parent: SceneKitView) { self.parent = parent }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let location = gesture.location(in: scnView)
            
            // --- TWO FINGER ROTATION ---
            if gesture.numberOfTouches == 2 {
                if let lastPos = lastFingerPosition {
                    let deltaX = Float(location.x - lastPos.x) * 0.01
                    let deltaY = Float(location.y - lastPos.y) * 0.01
                    parent.engine.rotateCamera(dx: deltaX, dy: deltaY)
                }
                lastFingerPosition = location
                return
            }
            
            // --- ONE FINGER FOLDING ---
            switch gesture.state {
            case .began:
                parent.dragStart = location
            case .changed:
                parent.dragEnd = location
            case .ended:
                if let start = parent.dragStart {
                    parent.engine.processFold(from: start, to: location, in: scnView)
                }
                parent.dragStart = nil
                parent.dragEnd = nil
                lastFingerPosition = nil
            default:
                break
            }
        }
    }
}

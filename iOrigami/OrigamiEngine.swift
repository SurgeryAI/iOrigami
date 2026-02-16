import SceneKit
import SwiftUI
import Combine

class OrigamiEngine: ObservableObject {
    @Published var foldCount: Int = 0
    var scene = SCNScene()
    var paperNode: SCNNode?
    var vertices: [SCNVector3] = []
    
    private var animationTimer: Timer?
    
    init() { setupScene() }
    
    func setupScene() {
        scene.rootNode.enumerateChildNodes { (node, _) in node.removeFromParentNode() }
        createPaper()
        addLights()
        foldCount = 0
    }
    
    private func createPaper() {
        let segments = 40
        vertices.removeAll()
        for y in 0...segments {
            for x in 0...segments {
                let vx = (Float(x) / Float(segments) - 0.5) * 10
                let vy = (Float(y) / Float(segments) - 0.5) * 10
                vertices.append(SCNVector3(vx, vy, 0))
            }
        }
        updateGeometry()
    }

    func processFold(from: CGPoint, to: CGPoint, in view: SCNView) {
        let hitStart = view.hitTest(from, options: nil).first?.localCoordinates
        let hitEnd = view.hitTest(to, options: nil).first?.localCoordinates
        guard let start = hitStart, let end = hitEnd else { return }
        
        let foldVector = SCNVector3(end.x - start.x, end.y - start.y, 0)
        let normal = SCNVector3(-foldVector.y, foldVector.x, 0)
        
        // Save original positions and calculate targets
        let originalVertices = vertices
        var targetVertices = vertices
        
        for i in 0..<vertices.count {
            let v = vertices[i]
            let toVertex = SCNVector3(v.x - start.x, v.y - start.y, v.z - start.z)
            let dot = toVertex.x * normal.x + toVertex.y * normal.y
            
            if dot > 0 {
                let dist = dot / (normal.x * normal.x + normal.y * normal.y)
                targetVertices[i].x -= 2 * dist * normal.x
                targetVertices[i].y -= 2 * dist * normal.y
                targetVertices[i].z += 0.2 // Stack height
            }
        }
        
        animateTo(targets: targetVertices)
        foldCount += 1
    }
    // Track if we are currently puffed to toggle back and forth
        @Published var isPuffed: Bool = false

        func applyPuff() {
            isPuffed.toggle()
            
            // We will create a target set of vertices that are "puffed"
            var targetVertices = vertices
            let amplitude: Float = isPuffed ? 0.4 : -0.4 // How much it bulges
            
            for i in 0..<targetVertices.count {
                let v = targetVertices[i]
                
                // Math: We use a sine wave based on the distance from the center
                // of the paper to create a natural "bulge" effect.
                let distance = sqrt(v.x * v.x + v.y * v.y)
                let puffAmount = cos(distance * 0.4) * amplitude
                
                targetVertices[i].z += puffAmount
            }
            
            // Reuse our joyful animation logic to "swell" the paper
            animateTo(targets: targetVertices)
            
            // Haptic feedback for the "pop"
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        }
    
    private func animateTo(targets: [SCNVector3]) {
        var step: Float = 0
        let totalSteps: Float = 20.0 // 20 frames of animation
        
        let startPositions = self.vertices
        
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
            step += 1
            let t = step / totalSteps
            
            for i in 0..<self.vertices.count {
                // Linear interpolation (Lerp)
                self.vertices[i].x = startPositions[i].x + (targets[i].x - startPositions[i].x) * t
                self.vertices[i].y = startPositions[i].y + (targets[i].y - startPositions[i].y) * t
                self.vertices[i].z = startPositions[i].z + (targets[i].z - startPositions[i].z) * t
            }
            
            self.updateGeometry()
            
            if step >= totalSteps {
                timer.invalidate()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
    
    private func updateGeometry() {
        let segments = 40
        var indices: [Int32] = []
        for y in 0..<segments {
            for x in 0..<segments {
                let i = Int32(y * (segments + 1) + x)
                indices.append(contentsOf: [i, i+1, i+Int32(segments)+1])
                indices.append(contentsOf: [i+1, i+Int32(segments)+2, i+Int32(segments)+1])
            }
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.white
        geometry.firstMaterial?.isDoubleSided = true
        geometry.firstMaterial?.lightingModel = .physicallyBased
        
        if paperNode == nil {
            paperNode = SCNNode(geometry: geometry)
            paperNode?.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(paperNode!)
        } else {
            paperNode?.geometry = geometry
        }
    }
    
    private func addLights() {
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(lightNode)
    }
}

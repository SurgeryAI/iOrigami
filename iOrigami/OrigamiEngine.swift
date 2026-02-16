import SceneKit
import SwiftUI
import Combine

class OrigamiEngine: ObservableObject {
    @Published var foldCount: Int = 0
    @Published var isPuffed: Bool = false
    
    // Scene Essentials
    var scene = SCNScene()
    var paperNode: SCNNode?
    var cameraOrbitNode = SCNNode() // The pivot for 2-finger rotation
    
    // Geometry Constants
    private let segments = 40
    private let paperSize: Float = 10.0
    var vertices: [SCNVector3] = []
    private var animationTimer: Timer?
    
    init() {
        setupScene()
    }
    
    // MARK: - Scene Setup
    func setupScene() {
        scene.rootNode.enumerateChildNodes { (node, _) in node.removeFromParentNode() }
        paperNode = nil
        foldCount = 0
        isPuffed = false
        
        // 1. Environment Lighting (Image-Based Lighting)
        // This gives the paper realistic "studio" reflections
        scene.lightingEnvironment.contents = "studio_lighting" // Uses system default or a provided HDR
        scene.lightingEnvironment.intensity = 1.2
        
        // 2. Camera & Orbit Pivot
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.position = SCNVector3(0, 0, 20)
        
        cameraOrbitNode = SCNNode()
        cameraOrbitNode.addChildNode(cameraNode)
        cameraOrbitNode.eulerAngles = SCNVector3(-Float.pi/4, 0, 0)
        scene.rootNode.addChildNode(cameraOrbitNode)
        
        // 3. Shadow-Casting Floor
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -2.0 // Lowered so "back-puffing" doesn't clip
        floorNode.geometry?.firstMaterial?.diffuse.contents = UIColor.systemGray6
        scene.rootNode.addChildNode(floorNode)
        
        addLights()
        createPaper()
    }
    
    private func addLights() {
        // Main Soft Spotlight for Shadows
        let spot = SCNLight()
        spot.type = .spot
        spot.castsShadow = true
        spot.shadowRadius = 10.0
        spot.shadowColor = UIColor(white: 0, alpha: 0.3)
        spot.intensity = 1200
        
        let lightNode = SCNNode()
        lightNode.light = spot
        lightNode.position = SCNVector3(10, 25, 10)
        lightNode.constraints = [SCNLookAtConstraint(target: scene.rootNode)]
        scene.rootNode.addChildNode(lightNode)
        
        // Soft Ambient Fill
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 300
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }
    
    // MARK: - Paper Creation
    private func createPaper() {
        vertices.removeAll()
        for y in 0...segments {
            for x in 0...segments {
                let vx = (Float(x) / Float(segments) - 0.5) * paperSize
                let vy = (Float(y) / Float(segments) - 0.5) * paperSize
                vertices.append(SCNVector3(vx, vy, 0))
            }
        }
        updateGeometry()
    }
    
    func updateGeometry() {
        var triangleIndices: [Int32] = []
        var lineIndices: [Int32] = []
        
        for y in 0..<segments {
            for x in 0..<segments {
                let i = Int32(y * (segments + 1) + x)
                let nextX = i + 1
                let nextY = i + Int32(segments) + 1
                let nextXY = i + Int32(segments) + 2
                
                triangleIndices.append(contentsOf: [i, nextX, nextY])
                triangleIndices.append(contentsOf: [nextX, nextXY, nextY])
                lineIndices.append(contentsOf: [i, nextX, i, nextY])
            }
        }
        
        let source = SCNGeometrySource(vertices: vertices)
        let faceElement = SCNGeometryElement(indices: triangleIndices, primitiveType: .triangles)
        let lineElement = SCNGeometryElement(indices: lineIndices, primitiveType: .line)
        
        let geometry = SCNGeometry(sources: [source], elements: [faceElement, lineElement])
        
        // Physically Based Paper Material
        let paperMat = SCNMaterial()
        paperMat.diffuse.contents = UIColor.white
        paperMat.lightingModel = .physicallyBased
        paperMat.roughness.contents = 0.4
        paperMat.isDoubleSided = true
        
        let creaseMat = SCNMaterial()
        creaseMat.diffuse.contents = UIColor.systemGray3
        creaseMat.lightingModel = .constant
        
        geometry.materials = [paperMat, creaseMat]
        
        if paperNode == nil {
            paperNode = SCNNode(geometry: geometry)
            paperNode?.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(paperNode!)
        } else {
            paperNode?.geometry = geometry
        }
    }
    
    // MARK: - Interactions
    func processFold(from: CGPoint, to: CGPoint, in view: SCNView) {
        let hitStart = view.hitTest(from, options: nil).first
        let hitEnd = view.hitTest(to, options: nil).first
        
        guard let start = hitStart?.localCoordinates, let end = hitEnd?.localCoordinates else { return }
        
        let dx = end.x - start.x
        let dy = end.y - start.y
        let normal = SCNVector3(-dy, dx, 0)
        
        var targetVertices = self.vertices
        var movedCount = 0
        
        for i in 0..<targetVertices.count {
            let v = targetVertices[i]
            let toV = SCNVector3(v.x - start.x, v.y - start.y, 0)
            let dot = toV.x * normal.x + toV.y * normal.y
            
            if dot > 0 {
                let lenSq = normal.x * normal.x + normal.y * normal.y
                let projection = dot / lenSq
                targetVertices[i].x -= 2 * projection * normal.x
                targetVertices[i].y -= 2 * projection * normal.y
                targetVertices[i].z += 0.25 // Incremental stacking
                movedCount += 1
            }
        }
        
        // Centering Pass (Bounding Box)
        let allX = targetVertices.map { $0.x }
        let allY = targetVertices.map { $0.y }
        if let minX = allX.min(), let maxX = allX.max(), let minY = allY.min(), let maxY = allY.max() {
            let cx = (minX + maxX) / 2.0
            let cy = (minY + maxY) / 2.0
            for i in 0..<targetVertices.count {
                targetVertices[i].x -= cx
                targetVertices[i].y -= cy
            }
        }
        
        if movedCount > 0 {
            animateTo(targets: targetVertices, duration: 0.4)
            foldCount += 1
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
    
    func applyPuff() {
        isPuffed.toggle()
        var targetVertices = vertices
        
        let allZ = vertices.map { $0.z }
        let medianZ = ((allZ.min() ?? 0) + (allZ.max() ?? 0)) / 2.0
        let power: Float = isPuffed ? 1.6 : 0.0
        
        for i in 0..<targetVertices.count {
            let v = targetVertices[i]
            let direction: Float = v.z >= medianZ ? 1.0 : -1.0
            let pocketShape = abs(sin(v.x * 0.7) * cos(v.y * 0.7))
            let expansion = pocketShape * power * (abs(v.z - medianZ) + 0.5)
            
            targetVertices[i].z += (expansion * direction)
        }
        
        animateTo(targets: targetVertices, duration: 0.7)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    func rotateCamera(dx: Float, dy: Float) {
        cameraOrbitNode.eulerAngles.y -= dx
        cameraOrbitNode.eulerAngles.x -= dy
        let limit = Float.pi / 2.2
        cameraOrbitNode.eulerAngles.x = max(-limit, min(limit, cameraOrbitNode.eulerAngles.x))
    }
    
    // MARK: - Animation Engine
    private func animateTo(targets: [SCNVector3], duration: TimeInterval) {
        var step: Double = 0
        let frameRate: Double = 60.0
        let totalSteps = duration * frameRate
        let startPositions = self.vertices
        
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/frameRate, repeats: true) { timer in
            step += 1
            let t = step / totalSteps
            let easedT = Float(t * (2 - t)) // Ease Out
            
            for i in 0..<self.vertices.count {
                self.vertices[i].x = startPositions[i].x + (targets[i].x - startPositions[i].x) * easedT
                self.vertices[i].y = startPositions[i].y + (targets[i].y - startPositions[i].y) * easedT
                self.vertices[i].z = startPositions[i].z + (targets[i].z - startPositions[i].z) * easedT
            }
            
            self.updateGeometry()
            if step >= totalSteps { timer.invalidate() }
        }
    }
}

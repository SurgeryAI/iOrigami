import SceneKit
import SwiftUI
import Combine

class OrigamiEngine: ObservableObject {
    @Published var foldCount: Int = 0
    @Published var isPuffed: Bool = false
    
    // Scene Essentials
    var scene = SCNScene()
    var paperNode: SCNNode?
    var cameraOrbitNode = SCNNode() // The "pivot" for camera rotation
    
    // Geometry Data
    var vertices: [SCNVector3] = []
    private var animationTimer: Timer?
    private let segments = 40
    private let paperSize: Float = 10.0
    
    init() {
        setupScene()
    }
    
    // MARK: - Setup
    func setupScene() {
        // 1. Completely clear the scene root
        scene.rootNode.enumerateChildNodes { (node, _) in
            node.removeFromParentNode()
        }
        
        // 2. IMPORTANT: Reset the local variable to nil so updateGeometry knows to recreate it
        paperNode = nil
        
        // 3. Reset the published states
        foldCount = 0
        isPuffed = false
        
        // 4. Re-setup Camera Pivot
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 20)
        cameraOrbitNode = SCNNode()
        cameraOrbitNode.addChildNode(cameraNode)
        cameraOrbitNode.eulerAngles = SCNVector3(-Float.pi/4, 0, 0)
        scene.rootNode.addChildNode(cameraOrbitNode)
        
        // 5. Re-setup Floor for shadows
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        // Inside setupScene()
        let floorNode = SCNNode(geometry: SCNFloor())
        floorNode.position.y = -0.5 // Lower the table slightly so the "back puff" has room
        scene.rootNode.addChildNode(floorNode)
        
        // 6. Restore lights and paper
        addLights()
        createPaper()
    }

    private func createPaper() {
        vertices.removeAll()
        for y in 0...segments {
            for x in 0...segments {
                let vx = (Float(x) / Float(segments) - 0.5) * paperSize
                let vy = (Float(y) / Float(segments) - 0.5) * paperSize
                // Always start at Z=0 for a fresh sheet
                vertices.append(SCNVector3(vx, vy, 0))
            }
        }
        // This will now correctly see that paperNode is nil and add it back to the scene
        updateGeometry()
    }
    
    private func addLights() {
        // Main Light with Soft Shadows
        let spotLight = SCNLight()
        spotLight.type = .spot
        spotLight.castsShadow = true
        spotLight.shadowRadius = 8.0
        spotLight.shadowSampleCount = 16
        spotLight.shadowColor = UIColor(white: 0, alpha: 0.3)
        spotLight.intensity = 1500
        
        let lightNode = SCNNode()
        lightNode.light = spotLight
        lightNode.position = SCNVector3(x: 10, y: 30, z: 15) // Higher and slightly to the side
        lightNode.constraints = [SCNLookAtConstraint(target: scene.rootNode)]
        scene.rootNode.addChildNode(lightNode)
        
        // Ambient fill
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        let aNode = SCNNode()
        aNode.light = ambient
        scene.rootNode.addChildNode(aNode)
    }
    
       
    // MARK: - Geometry Engine
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
        
        let paperMat = SCNMaterial()
        paperMat.diffuse.contents = UIColor.white
        paperMat.lightingModel = .physicallyBased

        // 'Roughness' helps show the "stretch" in the inflated areas
        paperMat.roughness.contents = 0.4
        paperMat.metalness.contents = 0.0 // Keep it feeling like paper fibers

        // This ensures that as the pockets puff toward the camera,
        // the edges get a slightly darker "rim" shadow.
        paperMat.fresnelExponent = 1.5
        
        let creaseMat = SCNMaterial()
        creaseMat.diffuse.contents = UIColor.systemGray2
        creaseMat.lightingModel = .constant
        
        geometry.materials = [paperMat, creaseMat]
        
        if paperNode == nil {
            paperNode = SCNNode(geometry: geometry)
            paperNode?.position.y = 0.05 // Lift for shadow room
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
        
        guard let startPoint = hitStart?.localCoordinates,
              let endPoint = hitEnd?.localCoordinates else { return }
        
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let normal = SCNVector3(-dy, dx, 0)
        
        var targetVertices = self.vertices
        var movedCount = 0
        
        // 1. Transformation (The Fold)
        for i in 0..<targetVertices.count {
            let v = targetVertices[i]
            let toVertexX = v.x - startPoint.x
            let toVertexY = v.y - startPoint.y
            let dot = toVertexX * normal.x + toVertexY * normal.y
            
            if dot > 0 {
                let lengthSq = normal.x * normal.x + normal.y * normal.y
                let projection = dot / lengthSq
                targetVertices[i].x -= 2 * projection * normal.x
                targetVertices[i].y -= 2 * projection * normal.y
                targetVertices[i].z += 0.2 // Stack layer height
                movedCount += 1
            }
        }
        
        // 2. Centering Logic
        let allX = targetVertices.map { $0.x }
        let allY = targetVertices.map { $0.y }
        if let minX = allX.min(), let maxX = allX.max(),
           let minY = allY.min(), let maxY = allY.max() {
            let offsetX = (minX + maxX) / 2.0
            let offsetY = (minY + maxY) / 2.0
            for i in 0..<targetVertices.count {
                targetVertices[i].x -= offsetX
                targetVertices[i].y -= offsetY
            }
        }
        
        if movedCount > 0 {
            animateTo(targets: targetVertices)
            foldCount += 1
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
    
    func applyPuff() {
        isPuffed.toggle()
        
        var targetVertices = vertices
        
        // 1. Find the Median Z (The "Air Pocket" center)
        let allZ = vertices.map { $0.z }
        let minZ = allZ.min() ?? 0
        let maxZ = allZ.max() ?? 0
        let medianZ = (minZ + maxZ) / 2.0
        
        // 2. Inflation Power
        let power: Float = isPuffed ? 1.4 : 0.0
        
        for i in 0..<targetVertices.count {
            let v = targetVertices[i]
            
            // 3. Determine Direction
            // If the vertex is above the middle, direction is 1 (Up)
            // If below the middle, direction is -1 (Down)
            let direction: Float = v.z >= medianZ ? 1.0 : -1.0
            
            // 4. Calculate Distance from the "Core"
            // This ensures the middle layers move less than the outer layers
            let distanceFromCore = abs(v.z - medianZ)
            
            // 5. The "Blowing Air" Math
            // We use a sine wave to create the 'bowing' of the facets,
            // and multiply by the direction so front and back puff away from each other.
            let pocketShape = sin(v.x * 0.7) * cos(v.y * 0.7)
            let expansion = abs(pocketShape) * power * (distanceFromCore + 0.5)
            
            // 6. Apply Movement
            // We push the vertex in its specific direction (forward or backward)
            targetVertices[i].z += (expansion * direction)
        }
        
        // Animate with a "breath-like" curve
        animateTo(targets: targetVertices, duration: 0.7)
        
        // Give the user a "hollow" sounding haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    func rotateCamera(dx: Float, dy: Float) {
        cameraOrbitNode.eulerAngles.y -= dx
        cameraOrbitNode.eulerAngles.x -= dy
        
        // Vertical clamping
        let limit = Float.pi / 2.2
        if cameraOrbitNode.eulerAngles.x > limit { cameraOrbitNode.eulerAngles.x = limit }
        if cameraOrbitNode.eulerAngles.x < -limit { cameraOrbitNode.eulerAngles.x = -limit }
    }
    
    // MARK: - Animation Engine
    private func animateTo(targets: [SCNVector3], duration: TimeInterval = 0.25) {
        var step: Double = 0
        let frameRate: Double = 60.0
        let totalSteps = duration * frameRate
        let startPositions = self.vertices
        
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/frameRate, repeats: true) { timer in
            step += 1
            let t = CGFloat(step / totalSteps)
            
            // Using a "Cubic Out" easing for a smoother, more organic arrival
            let easedT = Float(1 - pow(1 - t, 3))
            
            for i in 0..<self.vertices.count {
                self.vertices[i].x = startPositions[i].x + (targets[i].x - startPositions[i].x) * easedT
                self.vertices[i].y = startPositions[i].y + (targets[i].y - startPositions[i].y) * easedT
                self.vertices[i].z = startPositions[i].z + (targets[i].z - startPositions[i].z) * easedT
            }
            
            self.updateGeometry()
            
            if step >= totalSteps {
                timer.invalidate()
            }
        }
    }
}

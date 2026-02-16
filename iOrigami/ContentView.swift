import SwiftUI

struct ContentView: View {
    @StateObject private var engine = OrigamiEngine()
    
    // UI State for drawing the crease line
    @State private var dragStart: CGPoint? = nil
    @State private var dragEnd: CGPoint? = nil
    
    var body: some View {
        ZStack {
            // 1. The 3D Paper
            SceneKitView(engine: engine, dragStart: $dragStart, dragEnd: $dragEnd)
                .background(Color(UIColor.systemGray6))
                .edgesIgnoringSafeArea(.all)
            
            // 2. The Interaction Layer (Drawing the Crease)
            if let start = dragStart, let end = dragEnd {
                Canvas { context, size in
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    
                    // A "Joyful" blue crease line
                    context.stroke(path, with: .color(.blue.opacity(0.6)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 10]))
                    
                    // Add little circles at the ends
                    context.fill(Path(ellipseIn: CGRect(x: start.x-4, y: start.y-4, width: 8, height: 8)), with: .color(.blue))
                    context.fill(Path(ellipseIn: CGRect(x: end.x-4, y: end.y-4, width: 8, height: 8)), with: .color(.blue))
                }
                .allowsHitTesting(false) // Let touches pass through to SceneKit
            }
            
            // 3. UI Overlay
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("iOrigami")
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.black)
                        Text("\(engine.foldCount) Folds Made")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                
                Spacer()
                
                HStack(spacing: 30) {
                    // Puff Button
                    Button(action: { engine.applyPuff() }) {
                        VStack {
                            Image(systemName: engine.isPuffed ? "wind.snow" : "wind")
                                .font(.title)
                            Text(engine.isPuffed ? "Flatten" : "Puff Up")
                                .font(.caption).bold()
                        }
                        .frame(width: 80, height: 80)
                        .background(engine.isPuffed ? Color.blue : Color.white)
                        .foregroundColor(engine.isPuffed ? .white : .blue)
                        .clipShape(Circle())
                        .shadow(radius: 5)
                    }
                    
                    // Reset Button
                    Button(action: { engine.setupScene() }) {
                        VStack {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.title)
                            Text("Reset").font(.caption).bold()
                        }
                        .frame(width: 80, height: 80)
                        .background(Color.white)
                        .foregroundColor(.red)
                        .clipShape(Circle())
                        .shadow(radius: 5)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

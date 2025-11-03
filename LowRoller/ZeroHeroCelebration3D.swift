//
//  ZeroHeroCelebration3D.swift
//  LowRoller
//
//  Created by Thomas Plummer on 11/2/25.
//

import SwiftUI
import SceneKit
import UIKit

// MARK: - ZeroHeroCelebration3D
struct ZeroHeroCelebration3D: View {
    @State private var playToken = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()

            DiceChaosView(playToken: playToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Title + subhead (never wraps)
            VStack(spacing: 10) {
                Text("🎯 ZERO HERO! 🎯")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(.yellow)
                    .shadow(radius: 12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)   // shrink instead of wrapping
                    .allowsTightening(true)

                Text("All 3s — the ultimate low roll!")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.top, 48)
            .frame(maxHeight: .infinity, alignment: .top)

            // Lightweight confetti
            ConfettiView(
                isActive: .constant(true),
                intensity: 1.0,
                fallDuration: 3.5,
                colors: [.systemPurple, .systemYellow, .systemTeal, .systemPink]
            )
            .allowsHitTesting(false)
        }
        .onAppear { playToken &+= 1 } // replay burst each time this view appears
    }
}

// MARK: - SceneKit Wrapper (memory-optimized)
private struct DiceChaosView: UIViewRepresentable {
    let playToken: Int

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling2X     // lower AA to save memory
        v.preferredFramesPerSecond = 30           // reduce GPU load
        v.allowsCameraControl = false
        v.rendersContinuously = false
        v.isPlaying = true
        v.isUserInteractionEnabled = false          // no touch/focus
        v.isAccessibilityElement = false
        v.accessibilityElementsHidden = true
        v.accessibilityViewIsModal = false

        let scene = buildScene()
        context.coordinator.scene = scene
        v.scene = scene
        context.coordinator.lastToken = playToken

        NotificationCenter.default.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { _ in
            v.isPlaying = false
        }
        NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { _ in
            v.isPlaying = true
        }

        // Initial dice
        spawnDice(in: scene, screen: v.window?.windowScene?.screen)

        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        // On new token, "replay" by clearing dice nodes and respawning in the SAME scene.
        guard context.coordinator.lastToken != playToken,
              let scene = context.coordinator.scene else { return }

        context.coordinator.lastToken = playToken

        // Remove previous dice only (keep camera/lights/floor/walls)
        for n in scene.rootNode.childNodes where n.name == "lr_die" {
            n.removeFromParentNode()
        }
        spawnDice(in: scene, screen: v.window?.windowScene?.screen)
        v.scene = scene
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var lastToken = 0
        weak var scene: SCNScene?
    }

    // MARK: - Build static scene (camera/lights/floor/walls), then spawn dice
    private func buildScene() -> SCNScene {
        let scene = SCNScene()
        scene.physicsWorld.gravity = SCNVector3(0, -14, 0)

        // Camera (slightly elevated, looking down)
        let cam = SCNCamera()
        cam.fieldOfView = 60
        cam.wantsHDR = true
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 1.2, 9)
        let target = SCNNode()
        target.position = SCNVector3(0, -0.5, 0)
        scene.rootNode.addChildNode(target)
        let look = SCNLookAtConstraint(target: target)
        look.isGimbalLockEnabled = true
        camNode.constraints = [look]
        scene.rootNode.addChildNode(camNode)

        // Lights
        func omni(_ pos: SCNVector3, intensity: CGFloat) -> SCNNode {
            let l = SCNLight()
            l.type = .omni
            l.intensity = intensity
            let n = SCNNode()
            n.light = l
            n.position = pos
            return n
        }
        scene.rootNode.addChildNode(omni(SCNVector3(-6, 8, 10), intensity: 900))
        scene.rootNode.addChildNode(omni(SCNVector3( 6, 4,  6), intensity: 600))
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 300
        let ambNode = SCNNode(); ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // --- Invisible physics floor (thin box) — no SCNFloor, no "FloorPass" ---
        let floorBox = SCNBox(width: 20, height: 0.2, length: 20, chamferRadius: 0)
        let floorMat  = SCNMaterial()
        floorMat.diffuse.contents = UIColor.clear
        floorMat.lightingModel = .constant
        floorMat.writesToDepthBuffer = false
        floorMat.colorBufferWriteMask = []          // skip color writes entirely
        floorBox.materials = [floorMat]

        let floorNode = SCNNode(geometry: floorBox)
        floorNode.position = SCNVector3(0, -2.1, 0) // slightly below dice
        floorNode.physicsBody = .static()
        scene.rootNode.addChildNode(floorNode)

        // Invisible side walls (keep dice in-frame)
        func wall(x: Float? = nil, z: Float? = nil, w: CGFloat, h: CGFloat, l: CGFloat) -> SCNNode {
            let box = SCNBox(width: w, height: h, length: l, chamferRadius: 0)
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.clear
            m.lightingModel = .constant
            m.colorBufferWriteMask = []
            m.writesToDepthBuffer = false
            box.materials = [m]
            let n = SCNNode(geometry: box)
            n.physicsBody = .static()
            if let x = x { n.position.x = x }
            if let z = z { n.position.z = z }
            return n
        }
        scene.rootNode.addChildNode(wall(x: -4.5, w: 0.1, h: 6, l: 8))
        scene.rootNode.addChildNode(wall(x:  4.5, w: 0.1, h: 6, l: 8))
        scene.rootNode.addChildNode(wall(z: -4.0, w: 9,   h: 6, l: 0.1))

        // Initial dice

        // Clean up actions
        scene.rootNode.runAction(.sequence([
            .wait(duration: 6.0),
            .run { _ in scene.rootNode.childNodes.forEach { $0.removeAllActions() } }
        ]))

        return scene
    }

    // MARK: - Spawn a burst of dice (re-usable)
    private func spawnDice(in scene: SCNScene, screen: UIScreen?) {
        // Scale dice count by device capability (rough heuristic)
        let nativeHeight: CGFloat? = screen?.nativeBounds.height
        let isHighEnd = (nativeHeight ?? 0) >= 2778 // ~iPhone 12 Pro+ and up

        let count = isHighEnd ? 22 : 14

        for i in 0..<count {
            let die = makeDieNode(size: 0.52)
            die.name = "lr_die"
            die.position = SCNVector3(
                Float.random(in: -2.8...2.8),
                Float.random(in:  0.5...5.5),
                Float.random(in: -1.2...1.5)
            )
            die.opacity = 0
            scene.rootNode.addChildNode(die)

            // Stagger fade-in for fountain feel
            die.runAction(.sequence([
                .wait(duration: 0.02 * Double(i)),
                .fadeOpacity(to: 1.0, duration: 0.05)
            ]))

            // Impulse + torque
            die.physicsBody?.applyForce(
                SCNVector3(
                    Float.random(in: (-2.5)...2.4),
                    Float.random(in:  6.0...9.5),
                    Float.random(in: (-3.0)...(-1.0))
                ),
                asImpulse: true
            )
            die.physicsBody?.applyTorque(
                SCNVector4(
                    Float.random(in: (-1)...1),
                    Float.random(in: (-1)...1),
                    Float.random(in: (-1)...1),
                    Float.random(in:  8...16)
                ),
                asImpulse: true
            )
        }
    }

    // MARK: - Shared assets (textures & materials) to avoid per-die allocations
    private enum Assets {
        // 1) Pip textures cached once (6 UIImages)
        static let pipTextures: [UIImage] = {
            (1...6).map { face in
                let size = CGSize(width: 256, height: 256)
                let r = UIGraphicsImageRenderer(size: size)
                return r.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))

                    let pipColor = UIColor.black
                    let pipRadius: CGFloat = 16
                    func dot(_ x: CGFloat, _ y: CGFloat) {
                        let rect = CGRect(x: x - pipRadius, y: y - pipRadius,
                                          width: pipRadius*2, height: pipRadius*2)
                        ctx.cgContext.setFillColor(pipColor.cgColor)
                        ctx.cgContext.fillEllipse(in: rect)
                    }

                    let w = size.width, h = size.height
                    let gx: [CGFloat] = [w*0.22, w*0.5, w*0.78]
                    let gy: [CGFloat] = [h*0.22, h*0.5, h*0.78]

                    switch face {
                    case 1: dot(gx[1], gy[1])
                    case 2: dot(gx[0], gy[0]); dot(gx[2], gy[2])
                    case 3: dot(gx[0], gy[0]); dot(gx[1], gy[1]); dot(gx[2], gy[2])
                    case 4: dot(gx[0], gy[0]); dot(gx[2], gy[0]); dot(gx[0], gy[2]); dot(gx[2], gy[2])
                    case 5:
                        dot(gx[0], gy[0]); dot(gx[2], gy[0])
                        dot(gx[1], gy[1])
                        dot(gx[0], gy[2]); dot(gx[2], gy[2])
                    default:
                        dot(gx[0], gy[0]); dot(gx[2], gy[0])
                        dot(gx[0], gy[1]); dot(gx[2], gy[1])
                        dot(gx[0], gy[2]); dot(gx[2], gy[2])
                    }
                }
            }
        }()

        // 2) Materials cached once (6 SCNMaterial) using those textures
        static let materials: [SCNMaterial] = {
            pipTextures.map { img in
                let m = SCNMaterial()
                m.diffuse.contents = img
                m.lightingModel = .physicallyBased
                m.roughness.contents = 0.35
                m.metalness.contents = 0.05
                return m
            }
        }()
    }

    // MARK: - Die factory (reuses cached materials)
    private func makeDieNode(size: CGFloat) -> SCNNode {
        let box = SCNBox(width: size, height: size, length: size, chamferRadius: size * 0.06)
        box.chamferSegmentCount = 2            // lower segments to save memory/triangles
        box.materials = Assets.materials       // reuse, do NOT recreate per die

        let node = SCNNode(geometry: box)
        let body = SCNPhysicsBody.dynamic()
        body.mass = 1
        body.friction = 0.6
        body.rollingFriction = 0.9
        body.restitution = 0.25
        node.physicsBody = body
        return node
    }
}


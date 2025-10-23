//
//  ConfettiView.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/23/25.
//


import SwiftUI
import UIKit

struct ConfettiView: UIViewRepresentable {
    @Binding var isActive: Bool
    var intensity: CGFloat = 1.0           // 0.5 … 2.0 is sensible
    var fallDuration: TimeInterval = 3.0   // seconds confetti spawns
    var colors: [UIColor] = [
        .systemPink, .systemTeal, .systemYellow, .systemGreen,
        .systemOrange, .systemPurple, .systemBlue, .white
    ]

    func makeUIView(context: Context) -> ConfettiContainer {
        let view = ConfettiContainer()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ConfettiContainer, context: Context) {
        if isActive {
            uiView.startConfetti(colors: colors, intensity: intensity, duration: fallDuration)
        } else {
            uiView.stopConfetti()
        }
    }
}

/// UIView that hosts a CAEmitterLayer
final class ConfettiContainer: UIView {
    private var emitter: CAEmitterLayer?

    override class var layerClass: AnyClass { CAEmitterLayer.self }

    func startConfetti(colors: [UIColor], intensity: CGFloat, duration: TimeInterval) {
        guard emitter == nil else { return }

        let layer = self.layer as! CAEmitterLayer
        layer.emitterPosition = CGPoint(x: bounds.midX, y: -10) // emit from top
        layer.emitterShape = .line
        layer.emitterSize = CGSize(width: bounds.width, height: 1)

        // build cells
        var cells: [CAEmitterCell] = []
        let shapes: [ConfettiShape] = [.rectangle, .circle, .triangle, .diamond, .star]

        for color in colors {
            for shape in shapes {
                let cell = CAEmitterCell()
                cell.birthRate = 8 * Float(intensity)
                cell.lifetime = 6.0
                cell.velocity = 140 * intensity
                cell.velocityRange = 60 * intensity
                cell.emissionLongitude = .pi
                cell.emissionRange = .pi / 8
                cell.spin = 3
                cell.spinRange = 6
                cell.scale = 0.6
                cell.scaleRange = 0.3
                cell.yAcceleration = 120 * intensity
                cell.contents = ConfettiContainer.makeImage(color: color, shape: shape).cgImage
                cells.append(cell)
            }
        }

        layer.emitterCells = cells
        emitter = layer

        // stop spawning after `duration`, but let pieces finish falling
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            (self?.layer as? CAEmitterLayer)?.birthRate = 0
        }
    }

    func stopConfetti() {
        guard let layer = emitter else { return }
        // fade out existing particles and remove
        let fade = CABasicAnimation(keyPath: "birthRate")
        fade.fromValue = layer.birthRate
        fade.toValue = 0
        fade.duration = 0.25
        layer.add(fade, forKey: "birthRate")
        layer.birthRate = 0

        // remove after remaining particles die
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self] in
            guard let self = self else { return }
            (self.layer as? CAEmitterLayer)?.emitterCells = nil
            self.emitter = nil
        }
    }

    enum ConfettiShape { case rectangle, circle, triangle, diamond, star }

    static func makeImage(color: UIColor, shape: ConfettiShape, size: CGSize = CGSize(width: 12, height: 12)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            let rect = CGRect(origin: .zero, size: size)

            switch shape {
            case .rectangle:
                UIBezierPath(rect: rect).fill()
            case .circle:
                UIBezierPath(ovalIn: rect).fill()
            case .triangle:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: size.width/2, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.close(); path.fill()
            case .diamond:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: size.width/2, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height/2))
                path.addLine(to: CGPoint(x: size.width/2, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height/2))
                path.close(); path.fill()
            case .star:
                let path = UIBezierPath()
                let c = CGPoint(x: size.width/2, y: size.height/2)
                let r: CGFloat = min(size.width, size.height) * 0.5
                for i in 0..<10 {
                    let angle = CGFloat(i) * .pi / 5
                    let radius = i % 2 == 0 ? r : r * 0.45
                    let pt = CGPoint(x: c.x + radius * sin(angle), y: c.y - radius * cos(angle))
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                path.close(); path.fill()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // keep the emitter spanning the full width after rotations/resizes
        if let layer = self.layer as? CAEmitterLayer {
            layer.emitterPosition = CGPoint(x: bounds.midX, y: -10)
            layer.emitterSize = CGSize(width: bounds.width, height: 1)
        }
    }
}
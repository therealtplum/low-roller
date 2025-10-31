//
//  ConfettiView+Improved.swift
//  LowRoller
//
//  Performance-optimized confetti animation with caching and reduced particle count
//

import SwiftUI
import UIKit

struct ConfettiView: UIViewRepresentable {
    @Binding var isActive: Bool
    var intensity: CGFloat = 1.0
    var fallDuration: TimeInterval = 3.0
    var colors: [UIColor] = [
        .systemPink, .systemTeal, .systemYellow, .systemGreen,
        .systemOrange, .systemPurple, .systemBlue
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

/// Performance-optimized UIView that hosts a CAEmitterLayer
final class ConfettiContainer: UIView {
    private var emitter: CAEmitterLayer?
    
    // MARK: - Performance: Image Cache
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50 // Limit cache size
        cache.totalCostLimit = 1024 * 1024 * 2 // 2MB limit
        return cache
    }()
    
    override class var layerClass: AnyClass { CAEmitterLayer.self }
    
    deinit {
        emitter?.emitterCells = nil
        emitter = nil
    }
    
    // Prefer scale from context instead of deprecated UIScreen.main
    private var currentDisplayScale: CGFloat {
        if let scale = window?.windowScene?.screen.scale {
            return scale
        }
        if traitCollection.displayScale > 0 {
            return traitCollection.displayScale
        }
        return 1.0
    }

    func startConfetti(colors: [UIColor], intensity: CGFloat, duration: TimeInterval) {
        guard emitter == nil else { return }

        let layer = self.layer as! CAEmitterLayer
        layer.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        layer.emitterShape = .line
        layer.emitterSize = CGSize(width: bounds.width, height: 1)
        
        // Performance: Enable rasterization for better rendering
        layer.shouldRasterize = true
        layer.rasterizationScale = currentDisplayScale

        // Performance: Reduced particle variety
        var cells: [CAEmitterCell] = []
        let shapes: [ConfettiShape] = [.rectangle, .circle] // Reduced from 5 shapes
        let limitedColors = Array(colors.prefix(4)) // Limit to 4 colors max
        
        for color in limitedColors {
            for shape in shapes {
                let cell = createOptimizedCell(color: color, shape: shape, intensity: intensity)
                cells.append(cell)
            }
        }

        layer.emitterCells = cells
        emitter = layer

        // Stop spawning after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.fadeOutEmitter()
        }
    }
    
    private func createOptimizedCell(color: UIColor, shape: ConfettiShape, intensity: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        
        // Performance: Reduced birth rate and lifetime
        cell.birthRate = 4 * Float(intensity)
        cell.lifetime = 4.0
        cell.lifetimeRange = 1.0
        
        // Adjusted physics for smoother animation
        cell.velocity = 120 * intensity
        cell.velocityRange = 40 * intensity
        cell.emissionLongitude = .pi
        cell.emissionRange = .pi / 8
        
        // Reduced spin for better performance
        cell.spin = 2
        cell.spinRange = 3

        // 🔥 Bigger confetti size (was 0.5 / 0.2)
        cell.scale = 1.0
        cell.scaleRange = 0.4
        
        // Natural falling motion
        cell.yAcceleration = 150 * intensity
        
        // Use cached image
        let cacheKey = "\(shape.rawValue)-\(color.hash)" as NSString
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            cell.contents = cachedImage.cgImage
        } else {
            // 🔥 Slightly larger base image (was 10×10)
            let image = Self.makeImage(color: color, shape: shape, size: CGSize(width: 16, height: 16))
            Self.imageCache.setObject(image, forKey: cacheKey, cost: 100)
            cell.contents = image.cgImage
        }
        
        return cell
    }
    
    private func fadeOutEmitter() {
        guard let layer = emitter else { return }
        
        // Smooth fade animation
        let fade = CABasicAnimation(keyPath: "birthRate")
        fade.fromValue = layer.birthRate
        fade.toValue = 0
        fade.duration = 0.5
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        
        layer.add(fade, forKey: "fadeOut")
        layer.birthRate = 0
        
        // Clean up after particles finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.cleanupEmitter()
        }
    }

    func stopConfetti() {
        fadeOutEmitter()
    }
    
    private func cleanupEmitter() {
        (self.layer as? CAEmitterLayer)?.emitterCells = nil
        emitter = nil
    }

    enum ConfettiShape: String {
        case rectangle, circle
    }

    static func makeImage(color: UIColor, shape: ConfettiShape, size: CGSize = CGSize(width: 10, height: 10)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // Don't scale for retina, we handle that separately
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            let rect = CGRect(origin: .zero, size: size)

            switch shape {
            case .rectangle:
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 1)
                path.fill()
            case .circle:
                UIBezierPath(ovalIn: rect).fill()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let layer = self.layer as? CAEmitterLayer {
            layer.emitterPosition = CGPoint(x: bounds.midX, y: -10)
            layer.emitterSize = CGSize(width: bounds.width, height: 1)
        }
    }
}

// MARK: - SwiftUI Preview
struct ConfettiView_Previews: PreviewProvider {
    struct PreviewContainer: View {
        @State private var showConfetti = false
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    Button("Celebrate! 🎉") {
                        showConfetti = true
                        
                        // Auto-stop after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            showConfetti = false
                        }
                    }
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
                ConfettiView(isActive: $showConfetti)
                    .allowsHitTesting(false)
            }
        }
    }
    
    static var previews: some View {
        PreviewContainer()
    }
}

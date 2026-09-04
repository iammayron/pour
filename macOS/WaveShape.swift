import SwiftUI

/// Sine wave along the top edge, filled down to the bottom. `level` 0…1 = fill height.
struct WaveShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double = 5
    var wavelength: Double = 110

    func path(in rect: CGRect) -> Path {
        // Flatten the wave near empty/full so it never clips the edges.
        let amp = amplitude * min(1, level * 10, (1 - level) * 10)
        let baseY = rect.maxY - rect.height * level
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: 0.0, through: rect.width, by: 2) {
            let y = baseY + sin(x / wavelength * 2 * .pi + phase) * amp
            p.addLine(to: CGPoint(x: rect.minX + x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

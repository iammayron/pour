// Renders the Pour app icon. Usage:
//   swift scripts/render-icon.swift <outdir> [variant]     variants: pour (default), night, tumbler, flat, ring
//   swift scripts/render-icon.swift <outdir> --sheet       one PNG with every variant side by side
import SwiftUI
import AppKit

struct Wave: Shape {
    var level: Double; var phase: Double; var amp: Double; var wavelength: Double
    func path(in r: CGRect) -> Path {
        var p = Path(); let base = (r.maxY - amp) - r.height * level
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for x in stride(from: 0.0, through: r.width, by: 2) {
            p.addLine(to: CGPoint(x: r.minX + x, y: base + sin(x / wavelength * 2 * .pi + phase) * amp))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath(); return p
    }
}

let blue = Color(red: 0.145, green: 0.388, blue: 0.922)   // #2563EB, the card's water
let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)

func stream(_ color: Color, highlight: Color = .white.opacity(0.55), width: CGFloat = 60, height: CGFloat = 560, y: CGFloat = -200) -> some View {
    ZStack(alignment: .leading) {
        Capsule().fill(color)
        Capsule().fill(highlight).frame(width: width * 0.2).padding(.leading, width * 0.17).padding(.vertical, 8)
    }
    .frame(width: width, height: height).offset(y: y)
}

func splash(_ c: Color, y: CGFloat = 70) -> some View {
    ZStack {
        Ellipse().stroke(c.opacity(0.7), lineWidth: 12).frame(width: 200, height: 60).offset(y: y)
        Ellipse().stroke(c.opacity(0.35), lineWidth: 10).frame(width: 330, height: 100).offset(y: y)
        Circle().fill(c.opacity(0.8)).frame(width: 22).offset(x: -125, y: y - 50)
        Circle().fill(c.opacity(0.8)).frame(width: 16).offset(x: 130, y: y - 60)
        Circle().fill(c.opacity(0.7)).frame(width: 12).offset(x: -90, y: y - 90)
    }
}

/// 1024-pt canvas, 824-pt squircle (Apple's macOS icon grid).
struct Icon: View {
    var variant = "pour"
    var body: some View {
        ZStack {
            switch variant {
            case "night":   night
            case "tumbler": tumbler
            case "flat":    flat
            case "ring":    ring
            default:        pour
            }
        }
        .frame(width: 824, height: 824)
        .clipShape(squircle)
        .overlay(squircle.strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 6))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 16)
        .frame(width: 1024, height: 1024)
    }

    // A · current: light glass, blue water, stream from the top
    var pour: some View {
        ZStack {
            squircle.fill(LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 1), Color(red: 0.80, green: 0.87, blue: 1)], startPoint: .top, endPoint: .bottom))
            Wave(level: 0.46, phase: 0.6, amp: 22, wavelength: 420).fill(blue.opacity(0.45))
            Wave(level: 0.44, phase: 2.4, amp: 16, wavelength: 300).fill(blue.opacity(0.8))
            stream(blue)
            splash(.white)
        }
    }

    // B · night: deep navy glass, luminous water, white stream
    var night: some View {
        let glow = Color(red: 0.35, green: 0.65, blue: 1)
        return ZStack {
            squircle.fill(LinearGradient(colors: [Color(red: 0.13, green: 0.17, blue: 0.30), Color(red: 0.05, green: 0.07, blue: 0.15)], startPoint: .top, endPoint: .bottom))
            Wave(level: 0.46, phase: 0.6, amp: 22, wavelength: 420).fill(glow.opacity(0.45))
            Wave(level: 0.44, phase: 2.4, amp: 16, wavelength: 300).fill(glow.opacity(0.9))
                .shadow(color: glow.opacity(0.8), radius: 30)
            stream(.white.opacity(0.92), highlight: .white)
            splash(.white)
        }
    }

    // C · tumbler: a glass silhouette being filled, stream from the top right
    var tumbler: some View {
        let glass = RoundedRectangle(cornerRadius: 70, style: .continuous)
        return ZStack {
            squircle.fill(LinearGradient(colors: [Color(red: 0.86, green: 0.92, blue: 1), Color(red: 0.72, green: 0.82, blue: 1)], startPoint: .top, endPoint: .bottom))
            ZStack {
                glass.fill(Color.white.opacity(0.75))
                Wave(level: 0.55, phase: 0.6, amp: 16, wavelength: 300).fill(blue.opacity(0.5))
                Wave(level: 0.53, phase: 2.4, amp: 12, wavelength: 220).fill(blue.opacity(0.85))
            }
            .frame(width: 440, height: 520)
            .clipShape(glass)
            .overlay(glass.strokeBorder(Color.white.opacity(0.9), lineWidth: 14))
            .offset(y: 90)
            stream(blue, width: 52, height: 480, y: -180).rotationEffect(.degrees(24), anchor: .bottom)   // pours in from the top right, ends at the surface
            splash(.white, y: 60)
        }
    }

    // D · flat: bold single-color mark that survives 16 px
    var flat: some View {
        ZStack {
            squircle.fill(blue)
            Wave(level: 0.42, phase: 0.6, amp: 26, wavelength: 420).fill(Color.white.opacity(0.25))
            Wave(level: 0.40, phase: 2.4, amp: 18, wavelength: 300).fill(.white)
            Capsule().fill(.white).frame(width: 72, height: 520).offset(y: -230)
        }
    }

    // E · ring: timer ring with water rising inside the dial
    var ring: some View {
        ZStack {
            squircle.fill(LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 1), Color(red: 0.80, green: 0.87, blue: 1)], startPoint: .top, endPoint: .bottom))
            ZStack {
                Circle().fill(Color.white.opacity(0.8))
                Wave(level: 0.5, phase: 0.6, amp: 18, wavelength: 300).fill(blue.opacity(0.5))
                Wave(level: 0.48, phase: 2.4, amp: 12, wavelength: 220).fill(blue.opacity(0.85))
            }
            .frame(width: 540, height: 540).clipShape(Circle())
            Circle().trim(from: 0, to: 0.62).stroke(blue, style: StrokeStyle(lineWidth: 44, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 620, height: 620)
            Circle().stroke(blue.opacity(0.18), lineWidth: 44).frame(width: 620, height: 620)
        }
    }
}

struct Sheet: View {
    let variants = ["pour", "night", "tumbler", "flat", "ring"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(variants, id: \.self) { v in
                VStack(spacing: 24) {
                    Icon(variant: v).frame(width: 1024, height: 1024)
                    Icon(variant: v).frame(width: 1024, height: 1024).scaleEffect(64.0 / 1024).frame(width: 64, height: 64)
                    Text(v).font(.system(size: 64, weight: .medium)).foregroundStyle(.black)
                }
                .padding(40)
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.95))
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let out = args.first ?? "."
MainActor.assumeIsolated {
    if args.contains("--sheet") {
        let r = ImageRenderer(content: Sheet()); r.scale = 0.5
        let rep = NSBitmapImageRep(cgImage: r.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/sheet.png"))
        print("wrote \(out)/sheet.png"); return
    }
    let variant = args.count > 1 ? args[1] : "ring"
    for s in [16, 32, 64, 128, 256, 512, 1024] {
        let r = ImageRenderer(content: Icon(variant: variant)); r.scale = CGFloat(s) / 1024
        let rep = NSBitmapImageRep(cgImage: r.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(s).png"))
    }
    print("rendered \(variant)")
}

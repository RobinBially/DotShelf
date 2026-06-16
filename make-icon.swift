import AppKit

// Zeichnet ein einfaches, hübsches App-Icon und exportiert ein .iconset.

func makeIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.225

    // Hintergrund-Verlauf
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.42, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.30, blue: 0.85, alpha: 1)
    ])!
    gradient.draw(in: rect, angle: -45)

    // Stilisierte Klammern  { }  + Zeilen
    let lineColor = NSColor.white
    let s = size

    func stroke(_ p: NSBezierPath, width: CGFloat, color: NSColor = lineColor, alpha: CGFloat = 1) {
        color.withAlphaComponent(alpha).setStroke()
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    // linke geschweifte Klammer
    let lb = NSBezierPath()
    lb.move(to: NSPoint(x: s*0.40, y: s*0.24))
    lb.curve(to: NSPoint(x: s*0.30, y: s*0.40),
             controlPoint1: NSPoint(x: s*0.32, y: s*0.24),
             controlPoint2: NSPoint(x: s*0.34, y: s*0.34))
    lb.curve(to: NSPoint(x: s*0.22, y: s*0.50),
             controlPoint1: NSPoint(x: s*0.27, y: s*0.46),
             controlPoint2: NSPoint(x: s*0.22, y: s*0.50))
    lb.curve(to: NSPoint(x: s*0.30, y: s*0.60),
             controlPoint1: NSPoint(x: s*0.22, y: s*0.50),
             controlPoint2: NSPoint(x: s*0.27, y: s*0.54))
    lb.curve(to: NSPoint(x: s*0.40, y: s*0.76),
             controlPoint1: NSPoint(x: s*0.34, y: s*0.66),
             controlPoint2: NSPoint(x: s*0.32, y: s*0.76))
    stroke(lb, width: s*0.05)

    // rechte geschweifte Klammer (gespiegelt)
    let rb = NSBezierPath()
    rb.move(to: NSPoint(x: s*0.60, y: s*0.24))
    rb.curve(to: NSPoint(x: s*0.70, y: s*0.40),
             controlPoint1: NSPoint(x: s*0.68, y: s*0.24),
             controlPoint2: NSPoint(x: s*0.66, y: s*0.34))
    rb.curve(to: NSPoint(x: s*0.78, y: s*0.50),
             controlPoint1: NSPoint(x: s*0.73, y: s*0.46),
             controlPoint2: NSPoint(x: s*0.78, y: s*0.50))
    rb.curve(to: NSPoint(x: s*0.70, y: s*0.60),
             controlPoint1: NSPoint(x: s*0.78, y: s*0.50),
             controlPoint2: NSPoint(x: s*0.73, y: s*0.54))
    rb.curve(to: NSPoint(x: s*0.60, y: s*0.76),
             controlPoint1: NSPoint(x: s*0.66, y: s*0.66),
             controlPoint2: NSPoint(x: s*0.68, y: s*0.76))
    stroke(rb, width: s*0.05)

    // mittlere "Code-Zeilen"
    let lines: [(CGFloat, CGFloat)] = [(0.44, 0.62), (0.44, 0.50), (0.44, 0.56)]
    for (i, (x0, x1)) in lines.enumerated() {
        let y = s * (0.40 + CGFloat(i) * 0.10)
        let l = NSBezierPath()
        l.move(to: NSPoint(x: s*x0, y: y))
        l.line(to: NSPoint(x: s*x1, y: y))
        stroke(l, width: s*0.035, alpha: 0.9)
    }

    img.unlockFocus()
    return img
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./KonfigEditor.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (base, scale) in specs {
    let px = base * scale
    let icon = makeIcon(size: CGFloat(px))
    guard let tiff = icon.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try? png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("Iconset geschrieben nach \(outDir)")

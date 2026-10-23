import AppKit

// 生成 1024×1024 的 App 图标：蓝色圆角底 + 白色剪贴板符号。
// 用法：swift make-icon.swift <输出.png>

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let background = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedRed: 0.30, green: 0.62, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.10, green: 0.40, blue: 0.95, alpha: 1))!
        .draw(in: background, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let origin = NSPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    return true
}

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

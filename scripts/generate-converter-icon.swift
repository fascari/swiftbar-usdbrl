import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 24, dy: 24), xRadius: 220, yRadius: 220)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.27, alpha: 1),
    ending: NSColor(calibratedRed: 0.03, green: 0.39, blue: 0.37, alpha: 1)
)!
gradient.draw(in: background, angle: 135)

func drawCoin(_ rect: NSRect, color: NSColor, label: String, fontSize: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
    NSGraphicsContext.restoreGraphicsState()

    let text = NSAttributedString(string: label, attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    let textSize = text.size()
    text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
}

drawCoin(NSRect(x: 115, y: 427, width: 390, height: 390),
         color: NSColor(calibratedRed: 0.19, green: 0.43, blue: 0.79, alpha: 1),
         label: "$", fontSize: 255)
drawCoin(NSRect(x: 519, y: 207, width: 390, height: 390),
         color: NSColor(calibratedRed: 0.05, green: 0.65, blue: 0.48, alpha: 1),
         label: "R$", fontSize: 165)

let arrow = NSAttributedString(string: "↔", attributes: [
    .font: NSFont.systemFont(ofSize: 155, weight: .bold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.95),
])
let arrowSize = arrow.size()
arrow.draw(at: NSPoint(x: 512 - arrowSize.width / 2, y: 492 - arrowSize.height / 2))

image.unlockFocus()
guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:]),
    CommandLine.arguments.count == 2
else {
    fatalError("Could not render converter icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

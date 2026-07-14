import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate-icon.swift <iconset-directory> <icns-file>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let icnsURL = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let s = CGFloat(size)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    let tileRect = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1).setFill()
    tile.fill()

    let windowRect = NSRect(x: s * 0.13, y: s * 0.19, width: s * 0.74, height: s * 0.62)
    let window = NSBezierPath(roundedRect: windowRect, xRadius: s * 0.085, yRadius: s * 0.085)
    NSColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1).setFill()
    window.fill()

    let dividerY = windowRect.maxY - s * 0.24
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: windowRect.minX, y: dividerY))
    divider.line(to: NSPoint(x: windowRect.maxX, y: dividerY))
    divider.lineWidth = max(1, s * 0.012)
    NSColor(red: 0.73, green: 0.76, blue: 0.80, alpha: 1).setStroke()
    divider.stroke()

    let colors: [NSColor] = [
        NSColor(red: 0.98, green: 0.28, blue: 0.26, alpha: 1),
        NSColor(red: 1.00, green: 0.70, blue: 0.12, alpha: 1),
        NSColor(red: 0.16, green: 0.74, blue: 0.32, alpha: 1)
    ]
    let diameter = s * 0.16
    let gap = s * 0.045
    for (index, color) in colors.enumerated() {
        let circleRect = NSRect(
            x: windowRect.minX + s * 0.055 + CGFloat(index) * (diameter + gap),
            y: dividerY + (windowRect.maxY - dividerY - diameter) / 2,
            width: diameter,
            height: diameter
        )
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

var rendered: [Int: Data] = [:]
for (filename, size) in variants {
    let data = try rendered[size] ?? drawIcon(size: size)
    rendered[size] = data
    try data.write(to: outputDirectory.appendingPathComponent(filename))
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

let icnsEntries: [(String, Int)] = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64),
    ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)
]
var body = Data()
for (type, size) in icnsEntries {
    guard let png = rendered[size], let typeData = type.data(using: .ascii) else { continue }
    body.append(typeData)
    appendUInt32(UInt32(png.count + 8), to: &body)
    body.append(png)
}
var icns = Data("icns".utf8)
appendUInt32(UInt32(body.count + 8), to: &icns)
icns.append(body)
try FileManager.default.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try icns.write(to: icnsURL)

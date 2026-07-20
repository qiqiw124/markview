#!/usr/bin/env swift
import AppKit

let size = 1024.0
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = size * 0.225
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 圆角矩形背景
let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

// 渐变：蓝紫（#4F8CFF → #2563EB）
let gradient = NSGradient(
    colors: [
        NSColor(red: 0.31, green: 0.55, blue: 1.0, alpha: 1.0),  // #4F8CFF
        NSColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1.0)   // #2563EB
    ]
)!
gradient.draw(in: path, angle: 135)

// 白色 "M" 字
let fontSize: CGFloat = size * 0.52
let mFont = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
let attributes: [NSAttributedString.Key: Any] = [
    .font: mFont,
    .foregroundColor: NSColor.white
]
let mString = NSAttributedString(string: "M", attributes: attributes)
let mSize = mString.size()
let mOrigin = NSPoint(
    x: (size - mSize.width) / 2,
    y: (size - mSize.height) / 2 - size * 0.02
)
mString.draw(at: mOrigin)

NSGraphicsContext.restoreGraphicsState()

// 输出 PNG
let outputPath: String
if CommandLine.arguments.count > 1 {
    outputPath = CommandLine.arguments[1]
} else {
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
    outputPath = scriptDir + "/AppIcon.png"
}

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("ERROR: failed to encode PNG")
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("✅ AppIcon.png (\(pngData.count / 1024) KB) → \(outputPath)")

#!/usr/bin/env swift
/// ClaudeCommandHelper アプリアイコン生成スクリプト
/// ターミナルアイコン + 吹き出し形状のアイコンを生成し .icns に変換する

import Cocoa

let iconsetDir = "/tmp/ClaudeCommandHelper.iconset"
let icnsPath = "/tmp/ClaudeCommandHelper.icns"

// .iconset ディレクトリ作成
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

/// 指定サイズでアイコン画像を描画
func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // --- 背景: 角丸四角 ---
    let cornerRadius = s * 0.2
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // グラデーション背景（ダークネイビー）
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.08, green: 0.09, blue: 0.16, alpha: 1.0),
            CGColor(red: 0.14, green: 0.15, blue: 0.25, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])
    ctx.restoreGState()

    // --- 吹き出し形状 ---
    let bubbleInset = s * 0.12
    let bubbleRect = CGRect(
        x: bubbleInset,
        y: bubbleInset + s * 0.08,
        width: s - bubbleInset * 2,
        height: (s - bubbleInset * 2) * 0.72
    )
    let bubbleCorner = s * 0.08
    let arrowHeight = s * 0.07
    let arrowWidth = s * 0.1

    let bubble = CGMutablePath()
    // 本体（角丸）
    bubble.addRoundedRect(in: bubbleRect, cornerWidth: bubbleCorner, cornerHeight: bubbleCorner)
    // 矢印（下部中央やや左寄り）
    let arrowX = bubbleRect.midX - s * 0.05
    bubble.move(to: CGPoint(x: arrowX, y: bubbleRect.minY))
    bubble.addLine(to: CGPoint(x: arrowX - arrowWidth * 0.3, y: bubbleRect.minY - arrowHeight))
    bubble.addLine(to: CGPoint(x: arrowX + arrowWidth * 0.7, y: bubbleRect.minY))
    bubble.closeSubpath()

    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    ctx.addPath(bubble)
    ctx.fillPath()

    // --- ターミナルアイコン（SF Symbol） ---
    if let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: s * 0.28, weight: .medium)
        let configured = symbol.withSymbolConfiguration(symbolConfig)!

        let symbolSize = configured.size
        let symbolX = bubbleRect.midX - symbolSize.width / 2
        let symbolY = bubbleRect.midY - symbolSize.height / 2

        // シンボルの色を設定
        NSColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1.0).set()
        configured.draw(
            in: NSRect(x: symbolX, y: symbolY, width: symbolSize.width, height: symbolSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    image.unlockFocus()
    return image
}

/// NSImage を PNG Data に変換
func pngData(from image: NSImage, pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

// --- アイコンセット生成 ---
let sizes = [16, 32, 128, 256, 512]

for size in sizes {
    let image = renderIcon(size: size * 2) // 高解像度で描画

    // @1x
    let data1x = pngData(from: image, pixelSize: size)
    try! data1x.write(to: URL(fileURLWithPath: "\(iconsetDir)/icon_\(size)x\(size).png"))

    // @2x
    let data2x = pngData(from: image, pixelSize: size * 2)
    try! data2x.write(to: URL(fileURLWithPath: "\(iconsetDir)/icon_\(size)x\(size)@2x.png"))
}

print("Iconset generated at \(iconsetDir)")

// --- .icns に変換 ---
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Icon created at \(icnsPath)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
}

// makeicon — 生成「折光 Refract」的应用图标
//
// 设计意图：一束光从左下射入，打在斜放的镜面上折转 90°，
// 落到右上角发光的目标点上。看一眼就知道这是光线解谜。
// 深蓝底 + 青色辉光，和游戏里的配色一致。
//
// 编译运行：
//   swiftc -O makeicon.swift -o makeicon && ./makeicon

import AppKit
import CoreGraphics
import Foundation

let S: CGFloat = 1024
let outDir = "Refract.iconset"

// 图标方形区域（按 macOS 规范：824pt 居中，圆角 185）
let INSET: CGFloat = 100
let SIDE: CGFloat = 824
let RADIUS: CGFloat = 185

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

let cyan = color(0x4FE3E0)
let warm = color(0xFFD98A)
let bgTop = color(0x18243F)
let bgBottom = color(0x0A0E1A)

/// 多层描边做出辉光。macOS 没有现成的 shadow-blur 好用，
/// 就用"宽而淡 + 窄而亮"叠出光晕，成本低效果好。
func glowStroke(_ ctx: CGContext, _ pts: [CGPoint], _ c: CGColor, core: CGFloat) {
    let layers: [(CGFloat, CGFloat)] = [
        (7.0, 0.045), (4.2, 0.075), (2.4, 0.13), (1.35, 0.30),
        (0.75, 0.72), (0.38, 1.0),
    ]
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (mul, a) in layers {
        ctx.setStrokeColor(c.copy(alpha: a)!)
        ctx.setLineWidth(core * mul)
        ctx.beginPath()
        ctx.move(to: pts[0])
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }
}

func glowDot(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, _ c: CGColor) {
    let rings: [(CGFloat, CGFloat)] = [
        (3.4, 0.05), (2.2, 0.09), (1.5, 0.16), (1.0, 0.34), (0.62, 0.85),
    ]
    for (mul, a) in rings {
        ctx.setFillColor(c.copy(alpha: a)!)
        let rr = r * mul
        ctx.fillEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
    }
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
    let cr = r * 0.30
    ctx.fillEllipse(in: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2))
}

func render(size: CGFloat) -> Data {
    let scale = size / S
    let w = Int(size), h = Int(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("无法创建绘图上下文")
    }
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)
    // 统一在 1024 坐标系里作画，再进到 824 的图标区
    ctx.translateBy(x: INSET, y: INSET)

    let box = CGRect(x: 0, y: 0, width: SIDE, height: SIDE)
    let path = CGPath(roundedRect: box, cornerWidth: RADIUS, cornerHeight: RADIUS, transform: nil)

    // 背景
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if let g = CGGradient(colorsSpace: cs, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1]) {
        // 不加 drawsAfterEndLocation 的话，终点垂线之外不会绘制，角落会漏空
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: SIDE),
                               end: CGPoint(x: SIDE * 0.4, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    // 左上角一抹冷光，避免死板
    if let g = CGGradient(colorsSpace: cs,
                          colors: [cyan.copy(alpha: 0.14)!, cyan.copy(alpha: 0)!] as CFArray,
                          locations: [0, 1]) {
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 170, y: 700), startRadius: 0,
                               endCenter: CGPoint(x: 170, y: 700), endRadius: 460, options: [])
    }

    // 背景点阵，暗示这是一张网格棋盘
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.055))
    let step: CGFloat = 82
    var gy: CGFloat = 60
    while gy < SIDE - 40 {
        var gx: CGFloat = 60
        while gx < SIDE - 40 {
            ctx.fillEllipse(in: CGRect(x: gx - 4, y: gy - 4, width: 8, height: 8))
            gx += step
        }
        gy += step
    }
    ctx.restoreGState()

    // 内描边，让边缘立起来
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // 光路：横向入射 → 镜面 → 竖直射出
    let entry = CGPoint(x: 92, y: 300)
    let mirror = CGPoint(x: 500, y: 300)
    let exit = CGPoint(x: 500, y: 618)
    let target = CGPoint(x: 500, y: 668)

    glowStroke(ctx, [entry, mirror, exit], cyan, core: 26)
    glowStroke(ctx, [CGPoint(x: 40, y: 300), entry], cyan.copy(alpha: 0.55)!, core: 20)

    // 镜面：45° 亮条，中间白、两侧青
    let m: CGFloat = 92
    ctx.setLineCap(.round)
    let layers: [(CGFloat, CGFloat)] = [(3.0, 0.06), (1.8, 0.12), (1.0, 0.30)]
    for (mul, a) in layers {
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a))
        ctx.setLineWidth(30 * mul)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: mirror.x - m, y: mirror.y - m))
        ctx.addLine(to: CGPoint(x: mirror.x + m, y: mirror.y + m))
        ctx.strokePath()
    }
    ctx.setStrokeColor(CGColor(srgbRed: 0.92, green: 1, blue: 1, alpha: 0.98))
    ctx.setLineWidth(19)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: mirror.x - m, y: mirror.y - m))
    ctx.addLine(to: CGPoint(x: mirror.x + m, y: mirror.y + m))
    ctx.strokePath()

    // 目标点
    glowDot(ctx, target, 44, warm)

    guard let img = ctx.makeImage() else { fatalError("出图失败") }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("编码失败")
    }
    return data
}

// MARK: - 主流程

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, sz) in sizes {
    let data = render(size: sz)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("  \(name).png  \(Int(sz))px  \(data.count) bytes")
}

print("完成：\(outDir)")

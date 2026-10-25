// 折光 Refract — 光线解谜
// 仅用 Command Line Tools 即可编译
//
// 编译：
//   SDK=$(xcrun --show-sdk-path)
//   swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -parse-as-library -O main.swift -o Refract

import SwiftUI
import Foundation

// MARK: - 关卡

struct Level {
    let name: String
    let rows: [String]

    var width: Int { rows.first?.count ?? 0 }
    var height: Int { rows.count }
}

enum Levels {
    static let all: [Level] = [
        Level(name: "01 折下来", rows: [
            "........",
            ".>.../..",
            "........",
            "........",
            ".....T.."
        ]),
        Level(name: "02 接力", rows: [
            "........",
            ".>.../..",
            "........",
            "..T..\\..",
            "........"
        ]),
        Level(name: "03 串起来", rows: [
            "........",
            ".>.../..",
            "........",
            "..T.T\\..",
            "........"
        ]),
        Level(name: "04 三个弯", rows: [
            ".........",
            ".>..../..",
            ".........",
            ".........",
            "../...\\..",
            ".........",
            "..T......"
        ]),
        Level(name: "05 两路夹击", rows: [
            ".........",
            ".>.../...",
            ".........",
            ".....T...",
            ".........",
            ".>...\\...",
            "........."
        ]),
        Level(name: "06 固定镜", rows: [
            ".........",
            ".>....p..",
            ".........",
            "....../T.",
            "........."
        ]),
        Level(name: "07 长链", rows: [
            ".........",
            ".>....../",
            ".........",
            ".........",
            ".........",
            "..\\.....\\",
            "..T......"
        ]),
        Level(name: "08 各行其道", rows: [
            ".........",
            ".>...../.",
            ".........",
            ".........",
            "....T..T.",
            ".........",
            ".>..\\...."
        ]),
    ]
}

// MARK: - 几何

enum Dir {
    static let right = (1, 0), left = (-1, 0), up = (0, -1), down = (0, 1)

    static func from(_ c: Character) -> (Int, Int)? {
        switch c {
        case ">": return right
        case "<": return left
        case "^": return up
        case "v": return down
        default: return nil
        }
    }

    /// '/' 反射：(dx,dy) -> (-dy,-dx)
    /// '\' 反射：(dx,dy) -> (dy,dx)
    static func reflect(_ d: (Int, Int), _ mirror: Character) -> (Int, Int) {
        // '/' 与固定镜 'o' 同向，'\' 与固定镜 'p' 同向
        let isSlash = (mirror == "/" || mirror == "o")
        return isSlash ? (-d.1, -d.0) : (d.1, d.0)
    }
}

// MARK: - 游戏状态

struct Cell: Hashable {
    let x: Int
    let y: Int
}

@MainActor
final class Game: ObservableObject {
    @Published var levelIndex: Int = 0
    @Published var grid: [[Character]] = []
    @Published var moves: Int = 0
    @Published var solved: Set<Int> = []

    private let solvedKey = "refract.solved"

    init() {
        if let arr = UserDefaults.standard.array(forKey: solvedKey) as? [Int] {
            solved = Set(arr)
        }
        // 从第一个未通关的关卡开始
        if let first = Levels.all.indices.first(where: { !solved.contains($0) }) {
            levelIndex = first
        }
        // 开发期用：defaults write com.local.refract level -int 5 可直接跳关
        if let n = UserDefaults.standard.object(forKey: "level") as? Int,
           n >= 0, n < Levels.all.count {
            levelIndex = n
        }
        load(levelIndex)

        // 开发期用：把 demo 打开就直接解开当前关，方便看通关样式
        //   defaults write com.local.refract demo -bool YES
        let demo = UserDefaults.standard.bool(forKey: "demo")
            || CommandLine.arguments.contains("--demo")
        if demo, let sol = Self.solve(level: level) {
            for c in sol { tap(c) }
        }
    }

    var level: Level { Levels.all[min(levelIndex, Levels.all.count - 1)] }
    var isSolved: Bool { solved.contains(levelIndex) }

    func load(_ index: Int) {
        levelIndex = max(0, min(index, Levels.all.count - 1))
        grid = Levels.all[levelIndex].rows.map { Array($0) }
        moves = 0
        checkSolved()
    }

    func reset() {
        grid = level.rows.map { Array($0) }
        moves = 0
        checkSolved()
    }

    func next() {
        if levelIndex + 1 < Levels.all.count { load(levelIndex + 1) }
    }

    func prev() {
        if levelIndex > 0 { load(levelIndex - 1) }
    }

    /// 点击某个格子：如果可旋转镜子就翻转
    func tap(_ cell: Cell) {
        guard cell.y >= 0, cell.y < grid.count,
              cell.x >= 0, cell.x < grid[cell.y].count else { return }
        let c = grid[cell.y][cell.x]
        guard c == "/" || c == "\\" else { return }
        grid[cell.y][cell.x] = (c == "/") ? "\\" : "/"
        moves += 1
        checkSolved()
    }

    func isRotatable(_ cell: Cell) -> Bool {
        guard cell.y >= 0, cell.y < grid.count,
              cell.x >= 0, cell.x < grid[cell.y].count else { return false }
        let c = grid[cell.y][cell.x]
        return c == "/" || c == "\\"
    }

    private func checkSolved() {
        let (lit, _) = trace()
        let targets = allTargets()
        if !targets.isEmpty && targets.isSubset(of: lit) {
            if !solved.contains(levelIndex) {
                solved.insert(levelIndex)
                UserDefaults.standard.set(Array(solved), forKey: solvedKey)
            }
        }
    }

    func allTargets() -> Set<Cell> {
        var s = Set<Cell>()
        for (y, row) in grid.enumerated() {
            for (x, c) in row.enumerated() where c == "T" {
                s.insert(Cell(x: x, y: y))
            }
        }
        return s
    }

    /// 返回被点亮的格子，以及每条光线的路径（以格子坐标表示）
    func trace() -> (Set<Cell>, [[Cell]]) {
        Self.trace(grid: grid)
    }

    /// 纯函数版：给定任意棋盘，算出光路
    static func trace(grid: [[Character]]) -> (Set<Cell>, [[Cell]]) {
        var lit = Set<Cell>()
        var beams: [[Cell]] = []
        let h = grid.count
        let w = grid.first?.count ?? 0

        for y in 0..<h {
            for x in 0..<w {
                guard let startDir = Dir.from(grid[y][x]) else { continue }
                var d = startDir
                var path = [Cell(x: x, y: y)]
                var cx = x, cy = y
                for _ in 0..<(w * h * 4) {
                    let nx = cx + d.0, ny = cy + d.1
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { break }
                    cx = nx; cy = ny
                    path.append(Cell(x: cx, y: cy))
                    let cell = grid[cy][cx]
                    if cell == "#" { break }
                    if cell == "T" { lit.insert(Cell(x: cx, y: cy)) }
                    if cell == "/" || cell == "\\" || cell == "o" || cell == "p" {
                        d = Dir.reflect(d, cell)
                    }
                }
                beams.append(path)
            }
        }
        return (lit, beams)
    }

    // MARK: - 求解（开发期自检用）

    /// 枚举所有可旋转镜子的朝向，找出翻转次数最少的解。
    /// 返回需要翻转的格子；已经是解就返回空数组；无解返回 nil。
    static func solve(level: Level) -> [Cell]? {
        let base = level.rows.map { Array($0) }
        var rot: [Cell] = []
        var targets = Set<Cell>()
        for (y, row) in base.enumerated() {
            for (x, c) in row.enumerated() {
                if c == "/" || c == "\\" { rot.append(Cell(x: x, y: y)) }
                if c == "T" { targets.insert(Cell(x: x, y: y)) }
            }
        }
        guard rot.count <= 16 else { return nil }

        var best: [Cell]? = nil
        for mask in 0..<(1 << rot.count) {
            var g = base
            for (i, c) in rot.enumerated() {
                g[c.y][c.x] = (mask >> i) & 1 == 1 ? "/" : "\\"
            }
            let (lit, _) = trace(grid: g)
            guard !targets.isEmpty, targets.isSubset(of: lit) else { continue }
            var flips: [Cell] = []
            for c in rot where g[c.y][c.x] != base[c.y][c.x] {
                flips.append(c)
            }
            if best == nil || flips.count < best!.count {
                best = flips
                if flips.isEmpty { break }
            }
        }
        return best
    }
}

// MARK: - 配色

enum Palette {
    static let bg = Color(red: 0.055, green: 0.067, blue: 0.11)
    static let panel = Color(red: 0.09, green: 0.105, blue: 0.16)
    static let gridLine = Color(red: 1, green: 1, blue: 1).opacity(0.075)
    static let wall = Color(red: 0.22, green: 0.25, blue: 0.35)
    static let mirror = Color(red: 0.72, green: 0.78, blue: 0.9)
    static let beam = Color(red: 0.35, green: 0.85, blue: 1.0)
    static let targetOff = Color(red: 0.13, green: 0.15, blue: 0.21)
    static let targetOn = Color(red: 1.0, green: 0.78, blue: 0.35)
    static let source = Color(red: 0.55, green: 0.9, blue: 1.0)
}

// MARK: - 棋盘视图

struct BoardView: View {
    @ObservedObject var game: Game

    var body: some View {
        GeometryReader { geo in
            let cols = max(1, game.level.width)
            let rows = max(1, game.level.height)
            let pad: CGFloat = 18
            let cell = min((geo.size.width - pad * 2) / CGFloat(cols),
                           (geo.size.height - pad * 2) / CGFloat(rows))
            let boardW = cell * CGFloat(cols)
            let boardH = cell * CGFloat(rows)
            let ox = (geo.size.width - boardW) / 2
            let oy = (geo.size.height - boardH) / 2

            Canvas { ctx, _ in
                draw(ctx: &ctx, cell: cell, ox: ox, oy: oy, cols: cols, rows: rows)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let gx = Int(floor((value.location.x - ox) / cell))
                    let gy = Int(floor((value.location.y - oy) / cell))
                    game.tap(Cell(x: gx, y: gy))
                }
            )
        }
    }

    private func center(_ c: Cell, cell: CGFloat, ox: CGFloat, oy: CGFloat) -> CGPoint {
        CGPoint(x: ox + (CGFloat(c.x) + 0.5) * cell, y: oy + (CGFloat(c.y) + 0.5) * cell)
    }

    private func draw(ctx: inout GraphicsContext, cell: CGFloat,
                      ox: CGFloat, oy: CGFloat, cols: Int, rows: Int) {
        let (lit, beams) = game.trace()

        // 网格点
        for y in 0..<rows {
            for x in 0..<cols {
                let p = center(Cell(x: x, y: y), cell: cell, ox: ox, oy: oy)
                let r: CGFloat = 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Palette.gridLine))
            }
        }

        // 光路（多层描边做辉光）
        for beam in beams {
            guard beam.count > 1 else { continue }
            var path = Path()
            path.move(to: center(beam[0], cell: cell, ox: ox, oy: oy))
            for c in beam.dropFirst() {
                path.addLine(to: center(c, cell: cell, ox: ox, oy: oy))
            }
            let layers: [(CGFloat, Double)] = [
                (cell * 0.24, 0.05),
                (cell * 0.15, 0.09),
                (cell * 0.075, 0.20),
                (cell * 0.032, 0.95),
            ]
            for (w, a) in layers {
                ctx.stroke(path, with: .color(Palette.beam.opacity(a)),
                           style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
        }

        // 墙、镜子、目标、光源
        for y in 0..<rows {
            for x in 0..<cols {
                let ch = game.grid[y][x]
                let p = center(Cell(x: x, y: y), cell: cell, ox: ox, oy: oy)
                let s = cell * 0.62

                switch ch {
                case "#":
                    let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
                    ctx.fill(Path(roundedRect: r, cornerRadius: cell * 0.12),
                             with: .color(Palette.wall))

                case "/", "\\":
                    var path = Path()
                    let d = s / 2
                    if ch == "/" {
                        path.move(to: CGPoint(x: p.x - d, y: p.y + d))
                        path.addLine(to: CGPoint(x: p.x + d, y: p.y - d))
                    } else {
                        path.move(to: CGPoint(x: p.x - d, y: p.y - d))
                        path.addLine(to: CGPoint(x: p.x + d, y: p.y + d))
                    }
                    ctx.stroke(path, with: .color(Palette.beam.opacity(0.18)),
                               style: StrokeStyle(lineWidth: cell * 0.22, lineCap: .round))
                    ctx.stroke(path, with: .color(Palette.mirror),
                               style: StrokeStyle(lineWidth: cell * 0.10, lineCap: .round))

                case "o", "p":
                    // 固定镜子：多画一个方框表示不可动
                    var path = Path()
                    let d = s / 2
                    if ch == "o" {
                        path.move(to: CGPoint(x: p.x - d, y: p.y + d))
                        path.addLine(to: CGPoint(x: p.x + d, y: p.y - d))
                    } else {
                        path.move(to: CGPoint(x: p.x - d, y: p.y - d))
                        path.addLine(to: CGPoint(x: p.x + d, y: p.y + d))
                    }
                    ctx.stroke(path, with: .color(Palette.mirror.opacity(0.55)),
                               style: StrokeStyle(lineWidth: cell * 0.10, lineCap: .round))
                    let box = CGRect(x: p.x - s * 0.66, y: p.y - s * 0.66,
                                     width: s * 1.32, height: s * 1.32)
                    ctx.stroke(Path(roundedRect: box, cornerRadius: cell * 0.1),
                               with: .color(Palette.mirror.opacity(0.22)),
                               style: StrokeStyle(lineWidth: 1))

                case "T":
                    let on = lit.contains(Cell(x: x, y: y))
                    let r = s * 0.30
                    // 未点亮时是个暗色底座 + 虚线环，点亮后变成暖黄光点
                    if on {
                        let gr = r * 2.8
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - gr, y: p.y - gr,
                                                        width: gr * 2, height: gr * 2)),
                                 with: .radialGradient(
                                    Gradient(colors: [Palette.targetOn.opacity(0.30),
                                                      Palette.targetOn.opacity(0)]),
                                    center: p, startRadius: 0, endRadius: gr))
                        ctx.stroke(Path(ellipseIn: ring(p, r * 1.9)),
                                   with: .color(Palette.targetOn.opacity(0.28)),
                                   style: StrokeStyle(lineWidth: 1))
                    }
                    ctx.fill(Path(ellipseIn: ring(p, r)),
                             with: .color(on ? Palette.targetOn : Palette.targetOff))
                    if on {
                        ctx.fill(Path(ellipseIn: ring(p, r * 0.36)),
                                 with: .color(.white.opacity(0.92)))
                    } else {
                        ctx.stroke(Path(ellipseIn: ring(p, r)),
                                   with: .color(Palette.targetOn.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                        ctx.fill(Path(ellipseIn: ring(p, r * 0.24)),
                                 with: .color(Palette.targetOn.opacity(0.40)))
                    }

                default:
                    if let d = Dir.from(ch) {
                        let r = s * 0.30
                        let gr = r * 2.4
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - gr, y: p.y - gr,
                                                        width: gr * 2, height: gr * 2)),
                                 with: .radialGradient(
                                    Gradient(colors: [Palette.beam.opacity(0.16),
                                                      Palette.beam.opacity(0)]),
                                    center: p, startRadius: 0, endRadius: gr))
                        let tri = triangle(center: p, dir: d, size: r)
                        ctx.fill(tri, with: .color(Palette.source))
                        ctx.fill(Path(ellipseIn: ring(p, r * 0.42)),
                                 with: .color(.white.opacity(0.55)))
                    }
                }
            }
        }
    }

    private func ring(_ p: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    }

    private func triangle(center p: CGPoint, dir: (Int, Int), size: CGFloat) -> Path {
        var path = Path()
        let tip = CGPoint(x: p.x + CGFloat(dir.0) * size * 1.6,
                          y: p.y + CGFloat(dir.1) * size * 1.6)
        let perp = (-dir.1, dir.0)
        let a = CGPoint(x: p.x + CGFloat(perp.0) * size * 0.9 - CGFloat(dir.0) * size * 0.4,
                        y: p.y + CGFloat(perp.1) * size * 0.9 - CGFloat(dir.1) * size * 0.4)
        let b = CGPoint(x: p.x - CGFloat(perp.0) * size * 0.9 - CGFloat(dir.0) * size * 0.4,
                        y: p.y - CGFloat(perp.1) * size * 0.9 - CGFloat(dir.1) * size * 0.4)
        path.move(to: tip)
        path.addLine(to: a)
        path.addLine(to: b)
        path.closeSubpath()
        return path
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var game = Game()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            BoardView(game: game)
                .background(Palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal, 14)
            bottomBar
        }
        .frame(minWidth: 640, minHeight: 620)
        .background(Palette.bg)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.level.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(game.level.width)×\(game.level.height)　\(game.moves) 步")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            if game.isSolved {
                Text("已解开")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Palette.targetOn.opacity(0.18))
                    .foregroundStyle(Palette.targetOn)
                    .clipShape(Capsule())
            }
            Text("\(game.solved.count)/\(Levels.all.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                game.prev()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(game.levelIndex > 0 ? 0.75 : 0.18))
            .disabled(game.levelIndex == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("重来") { game.reset() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .keyboardShortcut("r", modifiers: [])

            Spacer()

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(game.isSolved ? Palette.targetOn.opacity(0.85)
                                               : .white.opacity(0.4))

            Spacer()

            Button {
                game.next()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(game.levelIndex < Levels.all.count - 1 ? 0.75 : 0.18))
            .disabled(game.levelIndex >= Levels.all.count - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hint: String {
        if game.isSolved { return "已解开　→ 下一关" }
        return "点击镜子让它转向"
    }
}

// MARK: - 入口

@main
struct RefractApp: App {
    init() {
        // 开发期自检：不开窗口，只打印每关最少步数
        if CommandLine.arguments.contains("--selftest") {
            var ok = 0
            for lv in Levels.all {
                if let sol = Game.solve(level: lv) {
                    let path = sol.map { "(\($0.x),\($0.y))" }.joined(separator: " ")
                    print("\(lv.name)  \(lv.width)x\(lv.height)  最少 \(sol.count) 步  \(path)")
                    ok += 1
                } else {
                    print("\(lv.name)  \(lv.width)x\(lv.height)  无解")
                }
            }
            print("---- \(ok)/\(Levels.all.count) 关可解")
            exit(ok == Levels.all.count ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup("折光") {
            ContentView()
        }
        .defaultSize(width: 820, height: 760)
        .windowResizability(.contentMinSize)
    }
}

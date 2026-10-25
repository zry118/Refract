# 折光 Refract

一束光，几面镜子，把光折到目标点上。点一下镜子它就转 90°，所有目标都亮起来就算过。

纯 SwiftUI 手写，没有第三方依赖，也不需要 Xcode —— 有 Command Line Tools 就能编译。

## 下载

到 [Releases](../../releases) 页面下载最新版 **Refract-1.0.zip**，解压后把
`Refract.app` 拖进「应用程序」文件夹。

首次启动 macOS 会拦截（个人开发者没有 $99/年的 Apple 公证）：右键点
app 图标 →「打开」→ 在弹窗里再点一次「打开」即可，之后照常启动。
也可以终端里跑一次 `xattr -cr /Applications/Refract.app` 永久放行。

- 系统要求：macOS 14.0+，**Apple Silicon**（M 系列芯片）

## 玩法

- 蓝色三角是光源，它朝哪个方向就射出哪条光
- 斜杠 `/` `\` 是可转的镜子，**点一下**就翻转
- 带方框的镜子是固定的，点不动，只能绕开它走
- 暖黄色的小圆点是要点亮的目标，全亮即通关
- 灰色方块是墙，光撞上就停

快捷键：`←` `→` 切关，`R` 重来。

进度存在 `~/Library/Preferences/com.local.refract.plist`，重开接着玩。

## 编译

```bash
cd ~/Projects/Refract
SDK=$(xcrun --show-sdk-path)
swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -parse-as-library -O main.swift -o Refract
```

`-parse-as-library` 不能省。省了 `@main` 会报
"cannot be used in a module that contains top-level code"。

## 打包

```bash
cp Refract Refract.app/Contents/MacOS/Refract
codesign --force --deep --sign - Refract.app
ditto -c -k --sequesterRsrc --keepParent Refract.app Refract-1.0.zip
```

## 图标

`makeicon.swift` 程序化画出来的，不依赖任何图片素材：

```bash
swiftc -O makeicon.swift -o makeicon && ./makeicon
iconutil -c icns Refract.iconset -o Refract.icns
```

画的是"光打在斜镜上折 90° 落到目标点"，和游戏里的核心动作一致。

## 关卡自检

改过关卡一定要跑一遍，它会暴力枚举所有镜面朝向，确认每关可解、并给出最少步数：

```bash
./Refract.app/Contents/MacOS/Refract --selftest
```

输出形如：

```
01 折下来  8x5  最少 1 步  (5,1)
...
---- 8/8 关可解
```

不可解时退出码为 1。

## 调试开关

```bash
# 直接跳到第 6 关（下标从 0 起）
defaults write com.local.refract level -int 5

# 启动时自动解开当前关，用来看通关样式
defaults write com.local.refract demo -bool YES

# 清掉进度
defaults delete com.local.refract refract.solved
```

## 文件

| 文件 | 作用 |
|---|---|
| `main.swift` | 全部代码：关卡数据、光路追踪、求解器、绘制、界面 |
| `makeicon.swift` | 图标生成器 |
| `validate_levels.py` | 独立写的 Python 关卡校验器，和 Swift 里的 `--selftest` 互为交叉验证 |
| `Refract.app` | 打包好的应用 |

## 光路规则

方向向量 `(dx, dy)`，`y` 向下：

- `/` 反射成 `(-dy, -dx)`
- `\` 反射成 `(dy, dx)`

固定镜 `o` 等价于 `/`，`p` 等价于 `\`。这个映射在 `Dir.reflect` 里，
渲染和追踪必须用同一套，否则会出现"看着该反射却直穿过去"的诡异现象。

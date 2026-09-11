# Wnip

Wnip 是一款使用 Swift、SwiftUI、AppKit 和 ScreenCaptureKit 构建的 macOS 菜单栏截图工具，支持截图、标注、复制、保存和贴图。

作者：**悟鸣** · [作者介绍与二维码](#作者)

## 功能

- **截图**：区域截图、窗口截图、全屏截图，支持多显示器与 Retina 屏幕。
- **截图加背景**：菜单选择区域、窗口或全屏截图加背景，也可在截图工具栏点击「添加背景」。支持纯色、六组可编辑渐变、内置图和本地图片；可调整画布比例、留白、圆角、阴影和白边，复制或保存，并显式保存默认样式。
- **标注**：矩形、椭圆、直线、箭头、画笔、马赛克、文字、高亮和步骤编号，支持撤销。
- **输出**：复制到剪贴板，保存为 PNG 或 JPEG；可设置 JPEG 质量、文件名规则、保存目录和截图阴影。
- **贴图**：把当前截图或本次运行中最近一张截图置顶显示，支持多张贴图、拖动和独立关闭。
- **设置**：自定义区域与窗口截图快捷键，配置完成通知、声音和触觉反馈。

## 使用

要求 macOS 15.0 或更高版本。从 [GitHub Releases](https://github.com/chujianyun/wnip/releases) 下载适合芯片类型的 DMG：

| Mac 芯片 | 安装包 |
| --- | --- |
| Apple Silicon（M 系列） | `Wnip-版本号-macOS-arm64.dmg` |
| Intel | `Wnip-版本号-macOS-x86_64.dmg` |

打开 DMG，将 `Wnip.app` 拖入其中的 Applications 文件夹。退出旧版本后再完整替换，唯一安装位置为 `/Applications/Wnip.app`，从该位置启动：

```bash
open /Applications/Wnip.app
```

Wnip 常驻菜单栏，不显示 Dock 图标。点击菜单栏图标可截图或打开 Settings。首次截图时按提示在系统设置的「隐私与安全性」中授予屏幕录制权限。

| 操作 | 默认快捷键 |
| --- | --- |
| 区域截图 | `⌘⇧X` |
| 窗口截图 | `⌘⇧W` |
| 全屏截图 | 菜单栏 → Capture Full Screen |
| 复制当前选区 | `Return`（不在编辑文字时） |
| 撤销标注 | `⌘Z` |
| 贴图 | `⌘⇧P` |
| 取消截图 / 关闭选中的贴图 | `Esc` |

选区确定后，可使用浮动工具栏标注、保存、复制或贴图。区域和窗口快捷键可在 Settings 中修改，贴图快捷键固定。更多贴图行为见 [贴图说明](docs/features/pinned-screenshots.md)。

## 开发与测试

准备完整的 Xcode（包含 macOS 15 或更新 SDK）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。本地已使用 Xcode 26.6、XcodeGen 2.46.0 验证。

```bash
git clone https://github.com/chujianyun/wnip.git
cd wnip
brew install xcodegen
xcodegen generate
xcodebuild test -project Wnip.xcodeproj -scheme Wnip \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

`project.yml` 是工程配置源，`Wnip.xcodeproj` 由 XcodeGen 生成，不纳入版本控制。上述关闭签名的命令仅用于测试；要安装的应用需使用有效签名。

## 构建 Release 包

打包脚本分别编译 Apple Silicon（arm64）与 Intel（x86_64）版本，生成两个带 Applications 快捷方式的 DMG 安装映像。准备钥匙串中的有效代码签名证书与私钥，将 `WNIP_SIGNING_IDENTITY` 设置为 `security find-identity -v -p codesigning` 列出的证书 SHA-1：

```bash
export WNIP_SIGNING_IDENTITY='替换为签名证书的 SHA-1'
bash scripts/package-release.sh 0.1.0
```

脚本会校验签名、可执行文件架构和磁盘映像完整性，拒绝覆盖已有同版本安装包。产物位于 `dist/`：

- `Wnip-0.1.0-macOS-arm64.dmg`
- `Wnip-0.1.0-macOS-x86_64.dmg`
- `Wnip-0.1.0-SHA256SUMS.txt`

在 GitHub Releases 创建对应版本的 Release，并上传这三个文件。可在下载目录执行 `shasum -a 256 -c Wnip-0.1.0-SHA256SUMS.txt` 校验文件。

`Release` 指构建配置，打包脚本不执行 Apple 公证或自动上传。当前安装包使用 Apple Development 证书签名，未经 Apple 公证，其他 Mac 可能受到 Gatekeeper 限制；正式分发需另行配置 Developer ID 签名及公证。Intel 包可在 Apple Silicon 上交叉编译，但不能据此宣称已经通过 Intel 真机验证。

重复安装时保持签名身份一致，避免影响已有系统授权。构建产物仅用于打包，实际运行验证须安装到 `/Applications/Wnip.app` 后进行，具体交付约定见 [AGENTS.md](AGENTS.md)。

## 目录

| 路径 | 内容 |
| --- | --- |
| `Wnip/App` | 应用入口与截图流程协调 |
| `Wnip/Capture` | 屏幕采集、选区和坐标转换 |
| `Wnip/Overlay` | 截图浮层与工具栏 |
| `Wnip/Annotation` | 标注模型与绘制 |
| `Wnip/Output` | 图片渲染、保存和贴图 |
| `Wnip/Preferences` | 偏好设置与快捷键录制 |
| `Wnip/System` | 系统权限、快捷键与反馈 |
| `WnipTests` | 自动化测试 |
| `docs` | 设计、实现计划与功能说明 |

## 作者

**悟鸣**，浙江省人工智能专家服务团专家、前蚂蚁集团高级 Agent 工程师、集团年度最受欢迎讲师、Qoder 大使、千问办公大使。

欢迎扫码交流，或关注公众号，了解 AI 与 Agent 实践。

<table>
  <tr>
    <th>悟鸣AI</th>
    <th>公众号</th>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/images/wuming-ai-qr.png" alt="悟鸣AI二维码" width="280" /></td>
    <td align="center" valign="top"><img src="docs/images/official-account-qr.jpg" alt="悟鸣公众号二维码" width="280" /></td>
  </tr>
</table>

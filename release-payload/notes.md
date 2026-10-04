## 新增

- 菜单新增「截图加背景」，支持区域、窗口和全屏截图；截图工具栏也可直接进入背景编辑。
- 支持纯色、六组可编辑渐变（含青绿极光）、两张内置背景及本地 PNG/JPEG/HEIC 图片导入。
- 可调整画布比例、留白、圆角、阴影、白色边框，以及背景图片的缩放和位置。
- 实时预览、按原始截图像素复制或保存，支持保存和恢复默认样式。

## 下载与安装

- Apple Silicon（M 系列）：下载 arm64 DMG。
- Intel：下载 x86_64 DMG。
- 要求 macOS 15.0 或更高版本。退出旧版，将应用完整替换到 `/Applications/Wnip.app` 后启动。
- 附 SHA-256 校验清单。安装包沿用 Apple Development 签名，未经 Apple 公证。

## 验证状态

- 185 项自动化测试全部通过，0 失败、0 跳过。
- 两架构安装包均完成签名、架构、版本及 DMG 完整性检查；Apple Silicon 版本已本机安装启动。
- 背景编辑界面的实际交互、屏幕录制权限及 Intel 真机运行仍待人工实测。
- [测试报告](https://github.com/chujianyun/wnip/blob/v0.2.0/docs/test-reports/2026-09-11-background-editor.md)

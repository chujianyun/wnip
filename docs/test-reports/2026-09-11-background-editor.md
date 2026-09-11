# 截图加背景测试报告

## 范围与环境

- 基线：`141c9ce`；独立功能分支 `codex/background-editor`。原工作区已有暂存、未暂存及未跟踪改动，本次未将这些改动纳入功能分支。
- macOS 26.6.2 (25G83)，Apple Silicon arm64；Xcode 26.6 (17F113)；最低支持 macOS 15。
- 新增菜单入口、背景编辑窗口、纯色/六组渐变/两张内置图/本地导入、布局样式、默认设置、复制保存。

## 自动化测试

命令：

```sh
xcodegen generate
xcodebuild test -quiet -project Wnip.xcodeproj -scheme Wnip \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

- 基线 166 项全部通过。
- 功能测试共 185 项：185 通过、0 失败、0 跳过（其中新增 19 项）。
- 首次扩展测试出现 2 项颜色断言失败，定位为测试通过 NSBitmapImageRep 读取后转为 sRGB 时引入显示器色彩配置转换。改为读取合成器明确标记为 sRGB 的原始像素后完整重跑通过；未放宽颜色断言。

| 场景 | 预期 | 实际 |
| --- | --- | --- |
| 自适应画布与留白 | 按截图短边计算留白，截图尺寸保持 | 通过 |
| 全部比例含自定义 | 原图完整包含、无拉伸、比例允许像素取整误差 | 通过 |
| 无效/极大尺寸 | 拒绝非法颜色、NaN、零比例和超过内存限制画布 | 通过 |
| 纯色与截图方向 | 颜色正确、不颠倒、画布不透明 | 通过 |
| 青绿极光 | 四角匹配指定 sRGB 色值 | 通过 |
| 全部渐变与线性方向 | 六预设及五角度可渲染 | 通过 |
| 预览与导出 | 相同比例与背景色，预览缩小不改变导出像素 | 通过 |
| 圆角、白边 | 白边和圆角位置正确 | 通过 |
| 图片背景 | 等比铺满和位置调整可用，缺图报错 | 通过 |
| 内置图 | 两张原创程序绘制背景可用 | 通过 |
| 默认样式 | 保存、重读、恢复初始默认 | 通过 |
| 导入持久化 | 原始文件移除后仍可读取应用保存的副本 | 通过 |
| 无效默认值 | 保存失败不覆盖原有默认样式 | 通过 |
| 三种截图入口 | 打开背景编辑器前不写剪贴板、不提前加阴影；确认导出后写入 | 通过 |
| 取消与普通截图 | 取消不打开编辑器，下一次普通截图不携带背景模式 | 通过 |

补充测试：取消/失败保存保留原图和设置、连续点击只导出一次、快速切换预览只展示最终样式、临时修改不覆盖已保存默认值，全部通过。

本地证据：`/tmp/wnip-background-evidence/test-summary.json`、`/tmp/wnip-background-tests.log`；完整 xcresult 在功能工作树 `DerivedData/Logs/Test`。

## 构建与安装验收

| 检查项 | 状态与证据 |
| --- | --- |
| Release 构建 | 通过，arm64，使用与旧安装一致的 Apple Development 身份；无 ad-hoc 降级 |
| 签名完整性 | 新旧应用 codesign --verify --deep --strict 通过 |
| 身份兼容 | 新产物满足旧安装 designated requirement，标识与 Team 保持一致 |
| 安装前停止 | 首轮旧 PID 22961、第二轮 PID 4709，核对可执行文件后 SIGTERM；均确认无 Wnip 残留才替换 |
| 完整替换 | 两轮均将旧包放入废纸篓备份后用 ditto 完整安装；安装后与本次 Release 可执行文件逐字节一致 |
| 启动路径 | `open /Applications/Wnip.app`，新 PID 5074，实际路径 `/Applications/Wnip.app/Contents/MacOS/Wnip` |
| 运行稳定 | 安装后进程持续存在，采样显示主线程正常等待事件 |
| UI 与实际输出 | 待完成。CUA 对只有状态栏的 Wnip 多次返回 timeoutReached/noWindowsAvailable；已请求用户手动打开编辑窗口后继续 |
| 屏幕录制权限实测 | 待实际截图验证；未清理或重置 TCC，仅签名兼容检查不能替代权限实测 |

构建命令：

```sh
xcodebuild build -quiet -project Wnip.xcodeproj -scheme Wnip \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$WNIP_SIGNING_IDENTITY" DEVELOPMENT_TEAM="$WNIP_DEVELOPMENT_TEAM"
```

命令中的身份与 Team 实际使用旧安装和本机钥匙串核对过的既有值。安装前首次 DR 检查命令缺少 `-R=` 中的等号而失败，未停止进程或覆盖旧包；纠正调用形式后通过。

本地产物：功能工作树 `DerivedData/Build/Products/Release/Wnip.app`。安装证据：`/tmp/wnip-background-evidence/stop.txt`、`install.txt`、签名基线与复查记录。状态栏以外的注册副本已经取消注册。

## Git 交付

用户在已告知界面实测未完成的情况下，明确要求推送代码并重新发布 GitHub Release。本轮按该指示发布 v0.2.0，保留 UI 与权限实测的未验证状态，不将其写为通过。


## v0.2.0 重新打包

- 执行 `WNIP_SIGNING_IDENTITY=已核对的既有证书指纹 bash scripts/package-release.sh 0.2.0`，两架构构建成功。
- Apple Silicon 和 Intel 的 DMG 均通过 hdiutil 校验；逐一只读挂载后复查应用签名、可执行文件架构、版本号 0.2.0，并与构建产物比较一致。
- 校验清单在 dist 目录通过 `shasum -a 256 -c Wnip-0.2.0-SHA256SUMS.txt` 验证。
- Apple Silicon 安装运行验证基于本机；Intel 为交叉构建与包内容检查，未进行 Intel 真机运行验证。
- 继续使用既有 Apple Development 证书签名，未做 Apple 公证。

| 文件 | SHA-256 |
| --- | --- |
| Wnip-0.2.0-macOS-arm64.dmg | b6f51983c99f7a1ed838e138266ded7c803ee9b1b4e5dfa545ccd2f1b2c404ce |
| Wnip-0.2.0-macOS-x86_64.dmg | 9c383891dd37ceb0be67ee5784f90a6272bad11cc886771201a8f78aa23fca3f |


## 发布完成记录（2026-09-12）

- 功能提交 `7b3a1b639ccbf3e9226ebaa4fb2e2f45e9abeca4` 已快进合并 main 并普通推送到 origin/main；v0.2.0 注释标签解析到同一提交。
- [GitHub Release v0.2.0](https://github.com/chujianyun/wnip/releases/tag/v0.2.0) 已正式发布并设为 Latest，非草稿、非预发布。
- 三份远端附件与本地文件的大小、SHA-256 均一致。远端校验使用 GitHub Releases API 的 asset digest，发布任务在校验通过后才解除草稿状态。
- [发布任务](https://github.com/chujianyun/wnip/actions/runs/34620548413) 成功。因本机 gh 未登录、浏览器附件接口受限，改用已有 SSH 权限推送独立发布分支，由 Actions 内置任务令牌上传。未新增或存储用户访问令牌，发布分支未合并 main。
- 本机已停止 PID 5074，确认无 Wnip 残留后安装本次 0.2.0 arm64 产物；启动 PID 6615，实际路径 `/Applications/Wnip.app/Contents/MacOS/Wnip`，Info.plist 版本为 0.2.0。安装后的可执行文件与打包产物逐字节一致，签名复查通过。
- 原工作区预先存在的暂存及未提交改动均保留，暂存补丁逐字节匹配合并前备份。原有预览功能与新背景入口的冲突已在未提交工作区中合并保留，未混入发布提交。
- 额外对恢复后的本地工作区（含原有未提交修改）执行完整测试：189 通过、0 失败、0 跳过。该结果用于确认保留原有修改后的工作区可用；v0.2.0 发布源码的测试结果仍为 185 项全部通过。
- 本轮最后的报告补充仅修改文档，不改变发布标签、应用源码或安装包。
- UI 实际交互、屏幕录制权限实测与 Intel 真机运行仍未验证，Release 说明中已明确列出。

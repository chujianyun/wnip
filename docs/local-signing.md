# 本地固定证书签名

使用 `bash scripts/install-local.sh` 构建和安装。脚本从 `project.yml`
读取固定的证书 SHA-1，要求钥匙串中存在对应的有效证书和私钥；找不到就停止，
不会回退到临时签名或其他开发证书。

- 证书 SHA-1：`DC86852A3142B093C0D6EF89F9978BC63349E0AF`
- 团队：`7PXD675DGC`
- Bundle ID：`com.wnip.app`
- 唯一安装位置：`/Applications/Wnip.app`
- 当前证书到期时间：2027-09-04 14:11:54 UTC。

Debug 和 Release 应用构建使用相同证书。不要用 `CODE_SIGNING_ALLOWED=NO`
或 `CODE_SIGN_IDENTITY=-` 构建要安装的版本；安装脚本会拒绝身份不匹配的产物。
私钥留在钥匙串中，不加入仓库。证书续期时需明确更新指纹，并重新检查系统授权兼容性。

脚本在替换应用前验证完整签名、Bundle ID 和证书指纹，取消其他应用副本的系统注册，
停止全部 Wnip 进程并确认退出。旧安装移入废纸篓，完整复制新产物后再次校验签名与
可执行文件内容，使用 `open /Applications/Wnip.app` 启动并验证运行路径。

## 2026-09-05 验证记录

- 完成两次 Release 构建、安装与启动，其中一次先执行 clean。
- `codesign --verify --deep --strict` 及固定证书要求校验通过。
- 原安装与两次新安装的 designated requirement 完全一致。
- 使用错误证书指纹的校验被正确拒绝。
- LaunchServices 中精确名为 Wnip.app 的注册仅保留 `/Applications/Wnip.app`。
- 实际进程路径为 `/Applications/Wnip.app/Contents/MacOS/Wnip`。
- 只读检查系统 TCC：ScreenCapture 的 `auth_value=2`；提取其现有 `csreq`
  并通过 `codesign --verify -R <requirement-file> /Applications/Wnip.app`，
  确认本次安装满足已保存的录屏授权身份要求。未修改或重置 TCC。
- `bash -n scripts/install-local.sh` 和 `git diff --check` 通过。
- 界面自动化多次连接 Wnip 超时，重置连接后仍未恢复；截图实际交互未完成验证。
  签名匹配验证不能代替实际截图测试，也不保证系统永远不再出现权限提醒。

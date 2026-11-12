# SingVerse 手机端

Flutter / Android 家庭 KTV 客户端，使用用户自备歌曲。手机连接 NAS 的 Go 主服务，支持家庭曲库、本机练唱与录音、作品回听导出，以及扫码参与电视 H5 点歌和授权电视登录。没有 iOS 工程；手机 minSdk 24，包名保持 `com.mynora.singverse.mobile`。

## 独立构建

```sh
make setup
make check
make build
```

需要 Flutter 3.47.5、Android SDK 36/Flutter 对应 NDK 及 JDK 21，使用仓库 Gradle Wrapper 与提交的 `pubspec.lock`。SDK 配置保存在忽略的 `android/local.properties`，不提交路径和凭据。`make build` 输出 `build/app/outputs/flutter-apk/app-debug.apk`。业务 API 契约快照和来源记录位于 [contracts](contracts/SOURCE.json)，测试不依赖兄弟仓库。Go 后端是契约权威，更新快照时记录具体 revision 和 SHA-256。

`VERSION` 是唯一产品版本来源；只接受 `major.minor.patch`，minor/patch 最大 999，`versionCode = major*1000000 + minor*1000 + patch`，必须为正且不超过 2100000000。每次正式发布提高版本，不能复用旧码。Flutter 的构建参数和 Android 包版本均从根 VERSION 注入，不在 pubspec 中维护第二份版本。

## 应用内更新

每次恢复或成功连接家庭 NAS 后异步检查一次（包括重新连接同一 NAS），之后仅在应用前台且距离上次检查满 24 小时再查。登录会话刷新不重复触发连接检查。“设置 → 应用更新”可随时手动检查。扫码 H5 的临时电视会话不作为更新来源。网络失败、未发布包或无新版本都不影响曲库和播放。

安装包由已连接 NAS 的公开同源接口 `GET /api/v1/client-releases/mobile` 和固定 `/api/v1/client-releases/mobile/apk` 提供。客户端只比较递增 versionCode；“跳过此版本”按 NAS 根地址和版本持久保存，手动检查仍可更新，新版本重新提醒。“稍后”只关闭本次提醒。

下载使用独立原生流式文件、进度、取消及重试；切换或断开 NAS 使旧任务失效。下载后校验大小、SHA-256、包名、版本名/码、minSdk、处理器架构和与已安装应用一致的证书。校验失败删除临时包。安装包最多 256 MiB，只共享更新缓存目录，不申请整盘存储权限。

每次用户确认安装或从安装来源权限页返回，都在后台重新流式核对缓存包的大小和 SHA-256，再复核包信息、连接代际和忙闲状态，通过后打开 Android 系统确认；Android 8+ 首次需允许本应用安装，返回后继续。录音、倒数、混音、麦克风试音和作品导出期间延后安装。覆盖更新保留本机作品、收藏和会话；debug 与正式签名不同，不能互相覆盖。首次正式安装应由发行方安排，不能承诺旧 debug 包直接无损转正式包。

## 正式发行

发行方长期保管固定签名，不把密钥放入仓库。设置 `SINGVERSE_MOBILE_KEYSTORE`、`SINGVERSE_MOBILE_STORE_PASSWORD`、`SINGVERSE_MOBILE_KEY_ALIAS`、`SINGVERSE_MOBILE_KEY_PASSWORD` 后执行：

```sh
make release
```

缺少正式签名立即失败，不回退 debug。输出 `build/mobile-release/singverse-mobile.apk`（通用 APK）、`release.json`、`SHA256SUMS`。元数据来自真实 APK 的 aapt/apksigner 结果，包含 versionCode/versionName、packageName、minSdk、abis、size、sha256、certificateSha256、notes；证书摘要为小写 64 位十六进制。APK 的源版本必须匹配根 VERSION。更新说明默认读取 `RELEASE_NOTES`，CI 使用 GitHub Release 正文；可用 `scripts/prepare-release.py --notes <文本文件>` 覆盖。说明最多 16000 UTF-8 字节。

GitHub Actions 在正式 GitHub Release `v<VERSION>` 发布后验证和构建上传资产；排除 draft/prerelease，普通 push/PR 只验证。仓库 Secrets：`MOBILE_KEYSTORE_BASE64`、`MOBILE_STORE_PASSWORD`、`MOBILE_KEY_ALIAS`、`MOBILE_KEY_PASSWORD`。签名文件仅暂存在 runner 临时目录并清理。发布前排除当前 tag、比较上一正式版本的元数据，拒绝版本不递增、缺失/损坏元数据或签名证书变化。无历史正式版本才允许首次发布。重试逐字节比对已上传资产，相同文件复用，仅上传缺失文件；不同内容失败，标签不可重用。管理平台镜像构建会下载并锁定正式 Release 中的 APK，用户从 NAS 下载，无需运行时访问 GitHub。

## 工程与验证

`lib/app` 提供标准/长辈布局、主题和迷你播放器，`lib/core` 管理 NAS、个人索引和更新状态，`features` 提供曲库、舞台、作品、电视及更新界面。Android 原生 `NasTransport` 管理加密 Cookie，`PlaybackService` 和 `KaraokeEngine` 提供 Media3 播放、AudioRecord、混音与作品导出；更新使用独立 `MobileUpdater`。平台唱录契约见 [mobile-karaoke](contracts/mobile-karaoke.md)。

`make check` 执行格式、分析、Flutter 行为测试及 Android 单元测试和发布边界测试（`make release-check` 可单独执行）。`make audio-test` 在独立 `.e2e` 应用运行原生设备检查。独立 UI 验收使用 `scripts/setup-mobile-karaoke-fixtures.py` 生成自制样本（需 FFmpeg，可用 `FFMPEG` 指定），另行启动隔离 Go/compute 后执行 `scripts/check-mobile-karaoke.py`；脚本只接受模拟器访问宿主的测试 NAS `10.0.2.2:18181`，不能连接日常 NAS。产物保存在 `build/reports/`，不入库。

自动化和模拟器不能替代真实手机麦克风、蓝牙、NAS 权限、微信扫码以及系统覆盖安装验证。真实安装验收需同一测试签名的两个递增版本，确认安装权限返回续装、拒绝/重试、跳过、新版本提醒和本机作品/会话保留。正式密钥、远程 GitHub Actions 与用户设备验收需发行环境完成。

项目技能索引见 [skills/README](skills/README.md)，保留第三方技能作者、许可和来源。

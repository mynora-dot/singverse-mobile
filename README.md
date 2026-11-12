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

## NAS 登录

连接页支持 HTTP / HTTPS，地址可输入 IP、域名和实际端口，也可粘贴完整根地址。切换协议不会自动降低 HTTPS 或跳过证书校验。管理员账号可修改，不再固定为 `admin`；NAS 启用二次验证时，仍需输入动态码或恢复码。

点击「查找局域网 NAS」通过 Android NSD 查找 `_singverse._tcp.` 服务，15 秒后结束，可重新查找或手动填写地址。进入后台或离开查找页时停止扫描。发现候选后只回填地址，登录前再次检查 `/api/v1/server-info`。Go 原生部署可配置 `SINGVERSE_TV_DISCOVERY_ADDRESS=<本机内网 IP>`、`SINGVERSE_TV_DISCOVERY_PORT=<实际 HTTP 入口端口>`；桥接 Docker 可在 NAS 宿主机用 Avahi 发布同类型服务，端口必须是手机能访问的入口。发现默认关闭；未发布 mDNS、访客 Wi-Fi 或隔离网络应手动填写地址。HTTPS 广告可带 `scheme=https` TXT 属性，否则按 HTTP 处理。

成功登录后记录曲库、地址、协议和账号，最多保留 20 条。历史页可回填、移除记录或单独忘记密码。勾选「记住密码」后，密码仅在登录和二次验证均成功后保存；取消勾选会立即移除该条已保存密码。历史及密码使用独立 Android Keystore AES-GCM 加密存储，不放入 Flutter SharedPreferences，不与 Cookie 或 WebView 共享。使用保存的密码前核对根地址、账号与 NAS instanceId；地址指向不同 NAS 时要求重新输入。退出会话保留用户主动记住的历史登录。

「忘记密码」使用现有 `POST /api/v1/auth/password/reset`，在应用内提供 Docker / 原生进程的一次性重置码获取说明、账号、重置码、新密码和确认密码表单。重置码由部署主机生成，15 分钟有效，新密码为 15～128 个 Unicode 字符。重置成功后返回登录，并清除此手机上同一 NAS 各地址保存的旧密码，保留其他曲库记录；服务端撤销所有设备会话并保留二次验证。客户端不会代替用户执行 NAS 上的恢复命令。

`test/connection_test.dart` 覆盖登录、历史、协议、身份隔离、二次验证、重置和小屏大字交互；`LoginVaultInstrumentedTest` 需在 Android 测试设备上验证 Keystore 加密与重启后读取，单元测试和 APK 编译不能代替真实 LAN/mDNS 与证书验收。

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

相关技能维护在项目外的用户技能目录（默认 `~/.codex/skills`），保留第三方技能作者、许可和来源；仓库不内置副本。

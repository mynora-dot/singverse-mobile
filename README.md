# SingVerse 手机端

Flutter / Android 家庭 KTV 客户端，使用用户自备歌曲。手机连接 NAS 的 Go 主服务，支持家庭曲库、本机练唱与录音、作品回听导出，以及扫码参与电视 H5 点歌。支持用已登录音乐库的 App 扫描电视登录码，在手机确认后将当前音乐库连接到电视，电视无需填写 IP；账号登录保留为备用方式。没有 iOS 工程；手机 minSdk 24，包名保持 `com.mynora.singverse.mobile`。

## 界面与动态效果（2026-11-18）

界面参照 [手机端苹果液态玻璃原型（2026-11-18）](../docs/手机端苹果液态玻璃原型-20261118/)，使用中性白色 / 黑色与深灰主题、红色品牌操作，默认跟随系统。这是 Flutter Android 对 Liquid Glass 的近似实现。浮动导航、搜索与迷你播放器使用局部扩散材质，选择了折射的少量小表面使用 shader；歌曲、歌词和普通表单保持稳定底色。长 sheet 使用 .98 中性底色与 18dp 局部模糊，无折射 shader；对话框没有全视口背景模糊，原生视频覆盖键不采样背景。

普通 / 长辈触控基准为 44 / 56dp，保留系统字号缩放与大字号滚动布局。普通模式已连接点歌页固定搜索和工具组，底部 dock 随列表滚动收拢 / 展开，收拢导航宽 144dp，与 compact 迷你播放器同行；键盘出现时隐藏整个 dock。长辈、录音中和大字号保持展开。底部内容留白读取 dock 实际高度，覆盖系统安全区。

「设置 → 性能模式」立即关闭界面动效与实时模糊，保留静态光影、播放进度和录音计时，不改变主题或「减少透明效果」偏好。系统 Reduce Motion 使用简化反馈；长辈模式、高对比度和减少透明效果使用不透明表面。实现约束与验收方式见 [Liquid Glass 设计与验证](docs/liquid-glass.md)。

设计文档顶部为当前规范，2026-11-17 及此前的蓝色材质参数、模拟器命令和验收记录明确归档为历史。本轮真机执行结果在设备验收完成后补充，旧报告不代表本轮已通过。

## 独立构建

```sh
make setup
make check
make build
```

需要 Flutter 3.47.5、Android SDK 36/Flutter 对应 NDK 及 JDK 21，使用仓库 Gradle Wrapper 与提交的 `pubspec.lock`。SDK 配置保存在忽略的 `android/local.properties`，不提交路径和凭据。`make build` 输出 `build/app/outputs/flutter-apk/app-debug.apk`。业务 API 契约快照和来源记录位于 [contracts](contracts/SOURCE.json)，测试不依赖兄弟仓库。Go 后端是契约权威，更新快照时记录具体 revision 和 SHA-256。

正式版本由 GitHub Release 标签 `vMAJOR.MINOR.PATCH` 决定，Actions 自动注入 `SINGVERSE_VERSION`；版本值只接受 `major.minor.patch`，minor/patch 最大 999，`versionCode = major*1000000 + minor*1000 + patch`，必须为正且不超过 2100000000。每次正式发布提高版本，不能复用旧码。Flutter 的构建参数和 Android 包版本均使用注入值，不在 pubspec 中维护第二份版本。本地调试默认 `0.0.0` / versionCode 1；本地正式打包需显式设置 `SINGVERSE_VERSION`。

## NAS 登录

连接页支持 HTTP / HTTPS，地址可输入 IP、域名和实际端口，也可粘贴完整根地址。切换协议不会自动降低 HTTPS 或跳过证书校验。管理员账号可修改，不再固定为 `admin`；NAS 启用二次验证时，仍需输入动态码或恢复码。

点击「查找局域网 NAS」通过 Android NSD 查找 `_singverse._tcp.` 服务，15 秒后结束，可重新查找或手动填写地址。进入后台或离开查找页时停止扫描。发现候选后只回填地址，登录前再次检查 `/api/v1/server-info`。Go 原生部署可配置 `SINGVERSE_TV_DISCOVERY_ADDRESS=<本机内网 IP>`、`SINGVERSE_TV_DISCOVERY_PORT=<实际 HTTP 入口端口>`；桥接 Docker 可在 NAS 宿主机用 Avahi 发布同类型服务，端口必须是手机能访问的入口。发现默认关闭；未发布 mDNS、访客 Wi-Fi 或隔离网络应手动填写地址。HTTPS 广告可带 `scheme=https` TXT 属性，否则按 HTTP 处理。

成功登录后记录曲库、地址、协议和账号，最多保留 20 条。历史页可回填、移除记录或单独忘记密码。勾选「记住密码」后，密码仅在登录和二次验证均成功后保存；取消勾选会立即移除该条已保存密码。历史及密码使用独立 Android Keystore AES-GCM 加密存储，不放入 Flutter SharedPreferences，不与 Cookie 或 WebView 共享。使用保存的密码前核对根地址、账号与 NAS instanceId；地址指向不同 NAS 时要求重新输入。退出会话保留用户主动记住的历史登录。

登录页的「自动登录」会同时勾选「记住密码」，成功登录并完成二次验证后生效。下次启动自动连接该 NAS：优先恢复同一账号的有效会话，会话失效时核对 NAS 身份后使用加密保存的密码重新登录。应用从后台回到前台时也会检查会话，过期后自动恢复同一 NAS 的登录；启动时网络不可达，可在网络恢复后重新打开应用重试。关闭自动登录后，下次启动需手动点击登录；取消记住密码、主动退出或重置密码也会关闭自动登录。密码错误时停止自动尝试，网络失败每次回到前台只尝试一次并显示错误，需要二次验证时仍由用户输入动态码或恢复码。升级前未设置该选项的既有用户继续沿用有效会话恢复行为。

「忘记密码」使用现有 `POST /api/v1/auth/password/reset`，在应用内提供 Docker / 原生进程的一次性重置码获取说明、账号、重置码、新密码和确认密码表单。重置码由部署主机生成，15 分钟有效，新密码为 15～128 个 Unicode 字符。重置成功后返回登录，并清除此手机上同一 NAS 各地址保存的旧密码，保留其他曲库记录；服务端撤销所有设备会话并保留二次验证。客户端不会代替用户执行 NAS 上的恢复命令。

`test/connection_test.dart` 覆盖登录、历史、协议、身份隔离、二次验证、重置和小屏大字交互；`LoginVaultInstrumentedTest` 需在 Android 测试设备上验证 Keystore 加密与重启后读取，单元测试和 APK 编译不能代替真实 LAN/mDNS 与证书验收。

## App 内管理端

「设置 → 管理端」在 App 内打开当前 NAS 的 `/admin/#/overview`，保留已配置的 HTTP / HTTPS 与端口；尚未连接时先进入 NAS 连接页。App 已登录时，原生层先向 NAS 核对当前账号和有效会话，再将该会话以同主机、HttpOnly Cookie 写入 WebView，完成后直接进入管理端，无需重复输入账号、密码或二次验证码。未登录 App 时清除管理网页的旧登录，仍可使用网页登录。记住的密码和会话值均不进入 Flutter 或网页脚本。

工具栏支持返回上一网页、刷新和直接关闭，系统返回键优先返回网页。加载失败可重试，HTTPS 证书错误不会放行；网页导航限制在当前 NAS 同源地址内。切换 NAS、退出或更换 App 账号后停止并卸载旧页面，需返回设置重新打开；关闭页面清理 WebView 的会话副本，保留 App 会话。管理网页主动退出会撤销同一服务端会话，App 下次请求也需重新登录。录音及混音期间提示完成后再打开，避免影响当前练唱。`test/admin_page_test.dart` 和 `AdminWebSessionTest` 覆盖登录同步、清理、导航、失败重试及连接切换；真实 Android WebView 与 NAS 的登录交互仍需设备验收。

扫码 H5 成功加入后，在当前 NAS 的网页持久存储中记住昵称；重新打开、重新扫码或断开电视后再次连接时自动回填，确认加入前可修改。参与凭据仍只留在本场的 sessionStorage，离开本场会清除参与身份并保留昵称；不会把管理员登录用于亲友点歌。此功能需同时更新 NAS 上的 H5 前端和手机 App。

## 应用内更新

每次恢复或成功连接家庭 NAS 后异步检查一次（包括重新连接同一 NAS），之后仅在应用前台且距离上次检查满 24 小时再查。登录会话刷新不重复触发连接检查。“设置 → 应用更新”可随时手动检查。扫码 H5 的临时电视会话不作为更新来源。网络失败、未发布包或无新版本都不影响曲库和播放。

安装包由已连接 NAS 的公开同源接口 `GET /api/v1/client-releases/mobile` 和固定 `/api/v1/client-releases/mobile/apk` 提供。客户端只比较递增 versionCode；“跳过此版本”按 NAS 根地址和版本持久保存，手动检查仍可更新，新版本重新提醒。“稍后”只关闭本次提醒。

下载使用独立原生流式文件、进度、取消及重试；切换或断开 NAS 使旧任务失效。下载后校验大小、SHA-256、包名、版本名/码、minSdk、处理器架构和与已安装应用一致的证书。校验失败删除临时包。安装包最多 256 MiB，只共享更新缓存目录，不申请整盘存储权限。

每次用户确认安装或从安装来源权限页返回，都在后台重新流式核对缓存包的大小和 SHA-256，再复核包信息、连接代际和忙闲状态，通过后打开 Android 系统确认；Android 8+ 首次需允许本应用安装，返回后继续。录音、倒数、混音、麦克风试音和作品导出期间延后安装。覆盖更新保留本机作品、练唱历史和会话；共享收藏保存在 NAS。debug 与正式签名不同，不能互相覆盖。首次正式安装应由发行方安排，不能承诺旧 debug 包直接无损转正式包。

## 正式发行

发行方长期保管固定签名，不把密钥放入仓库。设置 `SINGVERSE_MOBILE_KEYSTORE`、`SINGVERSE_MOBILE_STORE_PASSWORD`、`SINGVERSE_MOBILE_KEY_ALIAS`、`SINGVERSE_MOBILE_KEY_PASSWORD` 后执行：

```sh
SINGVERSE_VERSION=0.0.2 make release
```

缺少正式签名立即失败，不回退 debug。正式构建使用 `--split-per-abi`，只输出 ARMv7、ARM64、x86_64 三个单架构 APK：`build/mobile-release/singverse-mobile-{armeabi-v7a|arm64-v8a|x86_64}.apk`，另附 `release.json` 和 `SHA256SUMS`。不生成或上传通用 APK；各包 `versionCode` 均等于标签派生值，关闭 Flutter 的 ABI 版本号偏移。

`release.json` 使用 schemaVersion=2，公共字段包含 platform、versionCode/versionName、packageName、minSdk、certificateSha256、notes；variants 每项记录 abi、fileName、size、sha256。三个 APK 必须全部存在且各自只包含一个正确 ABI，版本和签名一致。元数据来自真实 APK 的 aapt/apksigner 结果，证书摘要为小写 64 位十六进制。历史 schemaVersion=1 清单仍用于签名连续性检查；同标签重试逐一比较全部架构文件。更新说明默认读取 `RELEASE_NOTES`，CI 使用 GitHub Release 正文；可用 `scripts/prepare-release.py --notes <文本文件>` 覆盖。说明最多 16000 UTF-8 字节。

应用内检查更新和下载通过 `X-SingVerse-ABI` 告知 NAS 设备架构；下载继续固定在当前 NAS 的 `/api/v1/client-releases/mobile/apk`，并固定使用已核对的清单架构。NAS 下载页提供各架构选择。需要同步更新 Go 镜像和下载页；新客户端继续支持旧 NAS 的通用包。旧客户端没有架构请求头，默认获取 ARM64，不支持该架构时先从下载页安装匹配架构的新版本。

GitHub Actions 仅在正式 GitHub Release（如 `v0.0.2`）发布后构建和上传资产；排除 draft/prerelease，普通 push/PR 不触发。工作流不运行测试、格式检查或静态分析，只保留发布版本、APK 签名和已有资产保护。仓库 Secrets：`MOBILE_KEYSTORE_BASE64`、`MOBILE_STORE_PASSWORD`、`MOBILE_KEY_ALIAS`、`MOBILE_KEY_PASSWORD`。签名文件仅暂存在 runner 临时目录并清理。发布前排除当前 tag、比较上一正式版本的元数据，拒绝版本不递增、缺失/损坏元数据或签名证书变化。无历史正式版本才允许首次发布。重试逐字节比对已上传资产，相同文件复用，仅上传缺失文件；不同内容失败，标签不可重用。管理平台镜像构建会下载并锁定正式 Release 中的 APK，用户从 NAS 下载，无需运行时访问 GitHub。

## 工程与验证

CI 固定使用 Ubuntu 24.04，保留 Android SDK/JDK，复用 Flutter 与 Gradle 依赖缓存。runner 中限制 Gradle 堆为 3 GiB、Kotlin daemon 堆为 1 GiB、并行 worker 为 2，不改变本地 Gradle 配置。GitHub Actions 缓存受 tag 访问范围限制，主要帮助同一 Release 的重跑，不保证不同版本之间命中。

`lib/app` 提供标准/长辈布局、主题和迷你播放器，`lib/core` 管理 NAS、个人索引和更新状态，`features` 提供曲库、舞台、作品、电视及更新界面。Android 原生 `NasTransport` 管理加密 Cookie，`PlaybackService` 和 `KaraokeEngine` 提供 Media3 播放、AudioRecord、混音与作品导出；更新使用独立 `MobileUpdater`。平台唱录契约见 [mobile-karaoke](contracts/mobile-karaoke.md)。

「常唱 → NAS 共享收藏」与后台「曲库 → 收藏」、电视收藏共用服务端数据。按钮提交明确的目标状态，收到 NAS 成功响应后才改变收藏状态；分页读取完整且修订一致的集合。页面进入、应用回到前台、写入后及前台约 30 秒重新读取；切 NAS、退出或登录失效清空旧集合，丢弃迟到响应。读取失败保留上次成功内容并标明，缺失歌曲可取消且不能播放。不读取、导入或上传旧 SQLite 收藏，也不持久化新收藏或建立离线写队列；同表练唱历史及录音作品保留。详见 [共享收藏契约](contracts/favorites.md)。

`make check` 提供格式、分析、Flutter 行为测试及 Android 单元测试和发布边界检查（`make release-check` 可单独执行）；`make audio-test` 提供独立 `.e2e` 原生设备检查。这些是工程入口说明，不是本轮执行记录。2026-11-18 界面改造的运行验收仅使用指定物理机 `YOUR_DEVICE_SERIAL`，不运行本机 unit / widget 测试或模拟器。

设备 runner 为 `scripts/check-player-console.py --target <target> --device <物理机序列号> --output <全新报告目录>`。`--target library_glass` 与 `--target nas_glass` 在真实手机渲染器上运行受控 UI fixture，不连接日常 NAS 或真实音频，不需要语音样本。`--target player_console` 为默认目标，验证实际原生播放与录音链路，必须额外提供 `--voice-sample <生成的 voice-test.wav>`；先用 `scripts/setup-mobile-karaoke-fixtures.py` 生成自制媒体（需 FFmpeg，可用 `FFMPEG` 指定），并启动新数据目录的隔离 Go / compute，经 adb reverse 连接 `127.0.0.1:18181`。

两层结果分别记录，UI fixture 不能代替真实 Media3、AndroidView、麦克风与 AAC 验收。runner 显式绑定物理机、拒绝模拟器、恢复测试前系统字号，仅更新 `.e2e` 包并保留日常应用与数据。旧 `scripts/check-mobile-karaoke.py` 的 `10.0.2.2:18181` 模拟器流程作为历史工具保留。产物保存在 `build/reports/`，不入库；命令、材质参数和本轮结果登记位置见 [Liquid Glass](docs/liquid-glass.md)。

自动化和模拟器不能替代真实手机麦克风、蓝牙、NAS 权限、微信扫码以及系统覆盖安装验证。真实安装验收需同一测试签名的两个递增版本，确认安装权限返回续装、拒绝/重试、跳过、新版本提醒和本机作品/会话保留。正式密钥、远程 GitHub Actions 与用户设备验收需发行环境完成。

相关技能维护在项目外的用户技能目录（默认 `~/.codex/skills`），保留第三方技能作者、许可和来源；仓库不内置副本。

## 扫码登录电视

手机和电视需同时安装支持本协议的构建。若手机仍提示「请扫描 SingVerse 电视上的聚会二维码」，请先更新手机 App；旧扫码入口还不能识别电视登录码。

在 App 登录音乐库后打开「电视」扫码，识别 `singverse://tv-login` 登录码与原有聚会邀请码。登录码会先展示电视名称与当前音乐库；确认后，原生桥接复用现有 `POST /api/v1/auth/tv-session` 并加密接力，Cookie 与 TV token 不进入 Flutter。手机与电视需在同一私有 IPv4 网络并可互访。取消、退出、后台或更换音乐库会取消本次尝试；失败时尽力撤销本次新建的电视凭据。原有扫码 H5 点歌流程保留。协议见 [TV 登录接力](contracts/tv-login-pairing.md)；界面与取消回归见 `test/tv_login_pairing_test.dart`。

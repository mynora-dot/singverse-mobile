# Liquid Glass 设计与验证

## 当前规范（2026-11-18）

当前实现对齐 [手机端苹果液态玻璃原型（2026-11-18）](../../docs/手机端苹果液态玻璃原型-20261118/)。这是 Flutter Android 对 Liquid Glass 的近似实现，不是 Apple 的原生材质 API，也没有新增 iOS 工程。下面记录本轮代码采用的规则；后面的历史记录保留旧参数和旧验收来源，不能用作本轮通过结论。

### 内容、材质与字体

浅色采用白色内容底，深色采用黑色 / 中性深灰；分组、弹层、环境光和阴影均去掉原有蓝色偏移。品牌和录音采用红色系，基础品牌色为 `#FA2D55`；浅色小号操作文字和录音按钮使用更深的红色，浅色主按钮配白字、深色主按钮配深色字，以保持可读性。练唱页面跟随浅深主题，视频保持真实比例和原生播放路径。连续歌曲、封面、歌词、长文本和表单依靠稳定底色与排版建立结构。

普通触控目标至少 44dp，长辈目标至少 56dp；部分操作保留更大尺寸。统一表单高度基准 52dp，内容最大宽度 720dp，页面边距基准 20dp，窄屏可收至 16dp。沿用系统字体和系统字号，正文基准 16sp，辅助文字基准至少 12sp、长辈至少 14sp；组件根据实际字号增加高度，长文本可换行或滚动。歌曲标题与时长不会因为玻璃效果进入滤镜输入。

`AppPalette` / `AppSurfaces` 管理颜色，`AppSpace` / `AppRadii` / `AppSizes` 管理几何，`GlassMaterialSpec` 管理材质。`GlassSurface` / `Glass` 是共同绘制入口，`GlassField` 保留输入焦点与控制器行为，`showAppSheet` / `showAppDialog` 保留路由取消、返回与焦点管理。

| 基础材质 | 浅 / 深染色不透明度 | 局部模糊 sigma | 折射 shader |
| --- | --- | --- | --- |
| `standard` | .82 / .84 | 18 | 无 |
| `search` | .88 / .90 | 24 | 无 |
| `floating` | .55 / .55 | 18 | 支持时启用 |
| `player` | .90 / .92 | 32 | 无，元数据保持稳定扩散 |
| `sheet` | .98 / .98 | 18 | 无 |
| `field` | .98 / .98 | 0 | 无 |
| `shortcut` | 1 / 1 | 0 | 无 |
| `onColor` | .18 / .18 | 12 | 无 |
| `stageControl` | .72 / .76 | 24 | 无 |
| `mediaOverlay` | .76 / .76 | 0 | 无 |

小型 regular 表面通过 `backdropContext` 参数接收布局提供的背景语义，取值为 `GlassBackdropContext.plain` / `content` / `media`，不逐帧读取屏幕像素。`plain` 保留基础参数；`content` 将染色提高到至少 .90 / .92、模糊至少 32；`media` 至少 .76 / .80、模糊至少 28。零模糊表面直接保留原参数，原生视频覆盖键与稳定表单不会因背景语义启用采样。导航与迷你播放器显式采用 `content`；通用 `GlassSearchField` 默认采用 `content`。

折射只用于选择了 `floating` 等折射材质的小表面。Impeller 支持时，`liquid_lens.frag` 在窄边缘做有限位移与中性亮度压缩；不支持或加载失败时使用局部模糊与对应色矩阵。反光改为单条局部柔和高光，按压光点跟随手指，没有常驻动画。每个透镜独立持有并释放 shader，前景文字不参与背景采样。

长 sheet 使用接近实体的 .98 中性底色、18dp 扩散且不启用折射，抑制粉红透底与大范围 shader 成本。弹层抓手提供 64×44dp 点击关闭区，短横视觉保留；内容由 `Flexible` 与自身滚动容器约束。对话框使用稳定底色；全视口背景模糊已移除。顶部工具栏渐隐、dock 底部渐隐和 `AppEnvironment` 都不使用全视口模糊。原生视频、相机与 WebView 路由的弹层使用实体表面，`mediaOverlay` 绘制时直接跳过滤镜。

### 主框架与辅助模式

点歌、常唱和作品共用吸顶头部。搜索与扫码 / 设置胶囊在宽度充足时同排，窄屏和大字号下紧凑分行。页面渐变铺满状态栏，操作控件在安全区内。列表回到顶部时操作区完全透明，向下滚动时逐步添加渐隐色和局部模糊。推荐卡来自第一首实际歌曲，搜索或筛选时恢复完整结果。

底部 dock 在列表向下滚动超过阈值后收拢，向上滚动或接近顶部时展开，切换标签时恢复展开。收拢状态通过独立 `ValueNotifier` 只重建底栏；动态底部留白由列表末尾的 `SliverBottomSpace` 局部订阅，避免 `Scaffold.extendBody` 更新 padding 时重建三个标签页的全部正文。Scaffold 仍更新实际底部布局和内容留白。收拢导航宽 144dp，容纳三个至少 44dp 的按钮；存在当前歌曲时与 compact 迷你播放器同行，窄屏隐藏 compact 封面并对标题做单行省略。键盘出现时整个 dock 立即隐藏。底部渐隐延伸到系统安全区，嵌入列表读取实际底部留白，列表末项可以滚动到 dock 上方。迷你播放器保持独立播放操作，点击或向上拖动进入播放器。

长辈模式、录音中以及系统字号将 16sp 放大到超过 21sp 时，dock 保持展开。导航、迷你播放器与页面内容继续保留系统字号缩放；长辈模式和大字号不展示密集推荐卡。性能模式、长辈模式、减少透明效果与高对比度使用实体材质，跳过实时模糊和折射。系统减少动态效果 / 辅助导航使用简化动效，透明度仍遵循独立偏好；Android 无跨版本统一的系统 Reduce Transparency 信号。

`AppMotion` 当前时长为按下 100ms、恢复 260ms、导航 360ms、页面 320ms、弹层 360ms、展开 280ms。减少动态效果只保留至多 100ms 的必要淡入，性能模式立即收束界面动画。媒体时钟、歌词、录音计时和网络请求不依赖动效完成。

设置中的性能模式开关采用正向语义：打开即启用性能模式，显示“已开启，停用动效与实时模糊”；关闭即退出性能模式，显示“已关闭，界面效果遵循外观设置”。保存的 `performanceMode` 布尔值与开关一致；关闭后继续遵循独立的减少透明效果、长辈模式和系统辅助设置。

“减少透明效果”同样使用正向开关：打开显示“已开启，使用清晰的不透明背景”，关闭显示“已关闭，使用常规透明效果”。若长辈模式或性能模式仍开启，关闭时明确说明该模式仍使用实底；不会因为关闭透明度偏好而退出其他模式。保存的 `reduceTransparency` 布尔值与该开关一致；减少透明效果本身不关闭动效。

### 本轮设备验证与命令

本轮所有运行验收仅使用已指定物理机 `YOUR_DEVICE_SERIAL`，使用隔离的 `.e2e` 包；不运行本机 unit / widget 测试或模拟器。验证分为两层，结果必须分开记录：

| runner target | 验证层 | 数据与能力边界 |
| --- | --- | --- |
| `library_glass` | 真机 UI fixture | 在真实 Flutter / Android 渲染器上检查主框架、搜索、筛选、dock、字号和材质；受控曲库与测试方法通道不证明真实 NAS、音频或相机链路 |
| `nas_glass` | 真机 UI fixture | 检查登录表单、焦点、键盘、浅深色与材质回退；内存数据与测试凭据不证明真实登录、证书或 Keystore 行为 |
| `player_console`（默认） | 真实原生链路 | 独立 NAS / compute、自制真实媒体以及实际 Media3、AndroidView、AudioRecord / AAC；需要生成的语音样本 |

统一入口为 `scripts/check-player-console.py --target <target>`。`--device` 和全新 `--output` 必填；`player_console` 和合并入口 `apple_prototype` 需要 `--voice-sample`。UI fixture 不需要语音样本，也不需要连接日常 NAS。

```sh
python3 scripts/check-player-console.py \
  --target library_glass \
  --device YOUR_DEVICE_SERIAL \
  --output build/reports/liquid-glass-20261118-library-new-run

python3 scripts/check-player-console.py \
  --target nas_glass \
  --device YOUR_DEVICE_SERIAL \
  --output build/reports/liquid-glass-20261118-nas-new-run
```

原生链路先使用新数据目录启动 `127.0.0.1:18181` 的独立 NAS / compute，并导入 `setup-mobile-karaoke-fixtures.py` 生成的自制媒体，再执行：

```sh
python3 scripts/check-player-console.py \
  --target player_console \
  --device YOUR_DEVICE_SERIAL \
  --voice-sample /absolute/path/to/generated/voice-test.wav \
  --output build/reports/liquid-glass-20261118-native-new-run
```

需要一次安装连续验证三套时，使用 `--target apple_prototype` 并提供同一 `--voice-sample`，各套截图按 `library/`、`nas/`、`player/` 保存，UI 报告汇入 `uiSuites`。测试表单偏好在内存中，真实播放仍走 NAS、Media3、AudioRecord 与本机 AAC。

重复验证同一包可添加 `--reuse-installed-apk`：runner 仍构建所选 target，只有本地 APK 与手机 `.e2e` 的 `base.apk` 完整 SHA256 一致才跳过安装；不一致或无法读取直接失败，不回退到安装或卸载。为了避免 vivo 丢失 logcat，测试包暂停启动，`scripts/phone_vm_log_bridge.dart` 直接订阅已验证的 loopback Dart VM Stdout / Stderr，READY 后由 driver 恢复执行；drive 使用 `--no-dds` 保持订阅。场景截图与字号、麦克风授权、语音样本播放标记均去重处理，原生验收同时核对四种控制标记全部到达。`vm.log` 和 `integration.log` 分别保留原始日志。

曲库性能采样使用 `wall-clock-gesture-v2`：`benchmarkLive` 下以真实时钟发送带时间戳的 8 次手势，每次 24 个移动事件；保留 500ms 惯性和界面变化尾段，按 vsync 开始时间纳入窗口内全部帧，不按耗时剔除帧。报告保留逐帧五阶段时间戳、手势时间和 callback drain 结果。设备报告的刷新率与实际应用帧率分开记录；16,667μs 是本轮 60Hz 参考预算，不代表已验证 120Hz。

省略 `--target` 等同于 `player_console`。runner 显式绑定物理机，使用 `.e2e` 覆盖安装和独立端口，不覆盖日常包或已有报告；结束后恢复测试前的系统字号与端口映射。截图、交互录屏、日志与帧统计保存在各自报告目录。帧采样前停止录屏和镜像，报告注明设备、构建模式、渲染器及采样范围；UI fixture 与真实原生播放的数据不能互相代替。60Hz 的 UI / Raster P95 ≤16.7ms 与超预算帧占比 <1% 是验收目标，只有本轮实际帧数据才能支持性能结论。

### 本轮执行结果

2026-11-18，物理机 vivo V2417A（`YOUR_DEVICE_SERIAL`），Android 15 / API 35，1260×2800、density 560（逻辑 360×800）。运行包为 `com.mynora.singverse.mobile.e2e`，profile / Impeller。所有运行测试均在这台手机完成，没有运行宿主 unit / widget 测试或模拟器；宿主执行静态分析、格式检查与 APK 构建。

`build/reports/apple-prototype-20261118/bundle-06/` 三套功能验收全部通过，包含曲库 / NAS UI fixture、21 项真实原生链路检查及 40 张场景截图。覆盖搜索、筛选草稿与取消、焦点和滚动保持、底栏收展与键盘避让、浅深色 / 不透明 / 性能 / 长辈模式，以及实际 Media3 播放、全屏返回、收藏、调音、音轨切换、选段应用 / 取消、拖动收起与迷你播放器展开、系统 200% 字号、AudioRecord / AAC 和录音回听。报告核对四种原生控制标记全部到达，结束后系统字号恢复为 1.0，日常包版本与更新时间保持不变。

真实录音报告时长 12,020ms，麦克风峰值 0.02373，voiceFrames 584,640、backingFrames 583,841、timestampAligned 为 true，保留 PREVIEW 且实际播放了生成的 AAC。语音样本由本轮自制 WAV 经宿主扬声器播放，由手机真实麦克风拾取；这证明采集与回听链路，不是音质专项结论。

| 原生场景（各 20 秒，`benchmarkLive`） | 帧数 | UI P95 | Raster P95 | 超 16.667ms 帧 |
| --- | ---: | ---: | ---: | ---: |
| 默认视频 | 1200 | 6.665ms | 7.318ms | 0% |
| 性能模式视频 | 1202 | 7.170ms | 4.112ms | 0% |
| 默认音频 / 歌词 | 1196 | 8.506ms | 8.485ms | 0.167% |

最终留白订阅修复后，仅在同一手机复测受影响的曲库 / 主框架，`build/reports/apple-prototype-20261118/library-03/` 全部交互通过，保存 18 张截图。每种模式使用约 7.24 秒真实手势窗口，callback drain 均完成，全部逐帧与手势记录保存在 `report.json`：

| 最终曲库滚动（`wall-clock-gesture-v2`） | 帧数 | UI P95 / 最大 | Raster P95 / 最大 | 超 16.667ms 帧 |
| --- | ---: | ---: | ---: | ---: |
| 默认玻璃 | 434 | 3.322 / 9.770ms | 6.326 / 14.444ms | 0 / 0% |
| 性能模式 | 431 | 2.698 / 10.677ms | 3.977 / 4.986ms | 0 / 0% |

对照 `bundle-06` 的同方法数据，修复前默认 4/419 帧超预算（0.955%，UI 最大 25.741ms），性能模式 7/424（1.651%，UI 最大 26.999ms）。最终窗口中两种模式均满足本轮 60Hz 参考目标；这是所列设备与样本窗口的实测结果，不外推为所有设备、热状态或 120Hz 的保证。NAS fixture 内快速切换协议的 pump 采样仅作交互诊断，不用于宣称真实时钟下的性能达标。

原生验证使用新数据目录和自制媒体，Go 来源 revision `44494661ffe4802b80cd5c442ad2d9295ee397b5`、compute 来源 revision `2663424657d406c05835276d2426e7608822cbae`，分别绑定宿主 loopback 18181 / 18190，不连接日常 NAS。原生播放器 / 录音代码在 `bundle-06` 后没有变更，最后一轮只修改主框架列表的底部留白订阅并执行对应曲库复测。

旧报告全部保留：`bundle-03` 是首轮三套通过记录；`library-02` 的功能测试通过，但旧 runner 因 vivo 丢失截图标记返回 1，性能模式慢帧 1.64%；`bundle-04` / `bundle-05` 是日志桥启动失败，尚未进入功能验收；`bundle-06` 修正启动参数和 DDS 接管后完成三套验收。不能将这些启动失败标为功能通过，也不能用旧 pump 曲库数据替代最终手势采样。

最终静态分析为 No issues found，64 个 Dart 文件格式检查无变化，`git diff --check` 通过；`sh scripts/build-apk.sh debug` 成功且 `pubspec.lock` 未变。开发产物为 `build/app/outputs/flutter-apk/app-debug.apk`，正式包名 `com.mynora.singverse.mobile`、开发版本 0.0.0 / code 1、minSdk 24 / targetSdk 36，Android Debug 签名验证通过；该开发 APK 只构建，没有覆盖手机上的日常应用。手机运行验收使用上文的 profile `.e2e` 包。

最终 ADB 结构化证据位于本地私有报告目录。已查看 `screenshots/current.png`，前台 Activity 为 `.e2e/com.mynora.singverse.mobile.MainActivity`，`/crash` 返回空记录。当前画面是曲库 fixture 最后打开的 NAS 表单，真实原生场景的证据在 `bundle-06/player/`。性能采样结束后才启动镜像采集。Codex 内嵌浏览器控制超时，浏览器验收未完成。测试后已核对系统字号恢复为 1.0，`stay_on_while_plugged_in` 已恢复原值 0。ADB 正反向端口映射均已清理，独立 NAS、compute 和镜像进程均已停止，相应端口已核对无监听。新增含设备序列号、日志或截图的原始报告可保存到仓库内的 `private-reports/`。

实际测试启动入口（runner 先订阅 VM 日志，再由 driver 恢复暂停的 isolate）：

```sh
adb -s YOUR_DEVICE_SERIAL shell am start \
  -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
  --ez start-paused true --ez enable-dart-profiling true \
  --ez enable-impeller true --ez disable-service-auth-codes true \
  com.mynora.singverse.mobile.e2e/com.mynora.singverse.mobile.MainActivity
```

本轮没有覆盖真实蓝牙路由 / 中断、实际相机扫码、WebView 登录、Keystore 专项、用户 NAS 权限及递增正式版本更新流程；这些不由受控 UI fixture 证明。

### 同日补充：两个开关的状态说明

性能模式与减少透明效果现在分别明确显示“已开启”或“已关闭”，开关打开即启用该项。减少透明效果关闭、但长辈模式或性能模式仍开启时，会明确说明该模式仍使用实底。原有正向布尔值、默认值和保存方式不变。

`build/reports/performance-switch-20261118/phone-02/` 在同一 vivo V2417A（`YOUR_DEVICE_SERIAL`）的 profile / Impeller `.e2e` 包通过曲库与主框架验收，保存 22 张截图。实际点击两个开关，检查状态文字、开关值、AppState、受控偏好值和渲染策略一致；返回设置后保持选中状态。减少透明效果单独开启时不关闭动效；性能模式开启后，再开关减少透明效果仍保持性能实底；退出两个模式后恢复外观效果。默认 / 性能模式滚动窗口分别纳入 437 / 436 帧，超 16.667ms 帧均为 0。该项为真实手机上的受控 UI fixture，不是新增原生播放 / 录音或跨进程偏好持久化专项验收。

状态截图为同目录的 `14-performance-switch-on.png`、`15-performance-switch-off.png`、`16-transparency-switch-on.png`、`17-transparency-switch-off.png`；功能结果与逐帧记录见 `acceptance.json` 和 `report.json`。`phone-01/` 保留加入减少透明效果调整前、性能模式单项通过的记录。本次没有启动镜像或打开浏览器面板，截图来自 runner 的 ADB 采集；启动入口与包名同上。字号核对为 1.0，ADB 正反向映射均为空，日常包版本与更新时间未变。

补充改动的 Dart 格式整理完成，完整 Flutter 静态分析为 No issues found；开发 APK 已重新构建成功，`pubspec.lock` 未变。产物仍为 `build/app/outputs/flutter-apk/app-debug.apk`，本次没有覆盖安装日常包。

## 历史设计与验收记录（截至 2026-11-17）

以下完整保留此前设计轮次与验证说明。蓝色品牌、蓝黑舞台、3–5dp 模糊、48dp 普通目标、340ms 导航等参数属于历史实现；模拟器命令和旧报告目录仅用于辨识来源，不代表 2026-11-18 当前规范或本轮验收结果。本轮操作方式以上方物理机说明为准。

### 历史：视觉层级

2026-11-17 第二轮重新调整了页面构图。点歌页以曲库第一首实际歌曲作为开唱卡片，该歌曲不在列表重复显示，搜索和筛选时恢复完整结果列表；歌手、分类与家庭歌单收为紧凑的同行入口。常唱页使用实际收藏封面与数量；作品草稿以原始录音波形呈现，缺失音频单独标记。未加入虚构推荐、封面或波形。

顶部扫码 / 设置共用玻璃工具栏，底部导航在普通模式下限制到 360dp，保留原点击区域。导航仅使用一层玻璃外壳，选中态以清蓝图标和较粗文字呈现，取消内部胶囊和边框。设置按家庭曲库、外观、使用体验分组。竖屏音频练唱采用横向封面与歌曲信息，扩大歌词阅读区域；视频和长辈模式保持原有安全布局。录音按钮采用高对比度红色与白字。

未连接时使用同一深蓝材质的连接引导，保留 NAS 错误提示并提供本机作品快捷入口，支持离线进入原有作品页面。冷启动与已连接状态分别保存验证截图。

NAS 登录页取消介绍段落、端口说明、自动登录说明和底部说明文字，仅保留必要标签、操作及错误反馈。左右留白 24dp，标题 28sp，输入框至少 60dp、圆角 18dp；协议与地址标签同行，账号和密码使用外置标签。无额外表单外框。

2026-11-17 NAS 材质升级增加 `GlassVariant.field` / `liquid`。`AppEnvironment` 在点歌、导航、表单、播放器之间共享背景坐标，以极淡的蓝色环境光提供透射信息，取消底部波浪和大面积彩色装饰。返回按钮悬浮、导航背景透明；状态栏根据主题选择图标明暗。输入框使用轻薄标准材质、3dp 局部模糊和单层细高光，没有扩散阴影；`GlassField` 观察子输入框焦点，过渡蓝色边缘光，不改变控制器、自动填充或键盘行为。

返回按钮、HTTP / HTTPS 选中块、迷你播放器使用光学透镜。`shaders/liquid_lens.frag` 通过 Flutter `ImageFilter.shader` 采样实际背景，圆角 SDF 法线将 6dp 边缘范围内的采样位置最多向内偏移 2.2dp、中心保持稳定；内层局部高斯散射先柔化背景，再由单次位移采样形成边缘透镜并按亮度调整底色，避免文字重影及重复纹理读取。`RenderLiquidLens` 使用绘制后的全局位置与设备像素比，避免把整个背景缩进控件，也不重复采样前景文字。边缘反射与内侧光线独立绘制；按压与指针只短暂改变高光，没有常驻动画。

这是 Flutter Android 的光学模拟，不是 iOS 26 原生 Liquid Glass API。Impeller 支持真实背景位移；Skia 或着色器加载失败时使用局部模糊、亮度压缩矩阵与相同的反射边缘，避免透出的背景大字成为黑影。程序仅加载一次，每个透镜独立持有并释放着色器。液态透镜不与重叠材质共享滤镜输入；原生视频、相机和 WebView 不进入采样层。

协议选中透镜沿轨道使用 340ms Spring 移动。重复点击已选协议不改变已保存凭据；切换协议、保存密码、自动登录、历史、发现、找回密码和二次验证仍沿用原行为。蓝色主按钮使用细渐变和按压光泽，禁用与加载条件不变。播放器使用轻玻璃播放键与内嵌进度条，保留独立底部空间，表单不会被遮挡。浮层淡入并调整自身高度；Reduce Motion 仅淡入，键盘出现时立即隐藏，退出阶段禁止点击与语义焦点。

性能模式、长辈模式、减少透明效果与高对比度使用不透明材质和可辨边缘，同时移除实时模糊与背景折射。系统减少动态效果和高对比度来自 Flutter `MediaQuery`；Android 没有跨版本统一的系统 Reduce Transparency 信号，透明度沿用应用现有的“减少透明效果”偏好。

开唱卡片的深蓝、白色文字和次要文字属于 `AppSurfaces` 语义 tokens；玻璃按标准、输入、悬浮和播放器分别设置浓度，配合单独校验的次要文字颜色，确保黑 / 白极端背景上的对比度至少 4.5:1。长辈模式和 200% 字号不展示密集开唱卡片，继续使用可换行、至少 56dp 的明确操作。

`AppSurfaces` 定义雾银 / 午夜背景、内容分组、玻璃染色、反光边缘和阴影；`singVerseTheme` 定义字体、清蓝操作色、录音红色、间距与圆角。正文基准 16，沿用系统字体与字号缩放。内容最大宽度 720dp，小屏和大字号允许换行、滚动。

`GlassSurface` 用于导航、工具栏、迷你播放器和弹层，模糊严格裁切到组件范围，浓度由静态渐变覆盖。标准交互材质与悬浮透镜共用同一个光学绘制实现；相同 3dp 模糊且互不重叠的输入框和快捷入口在 BackdropGroup 中合并滤镜。每个透镜独立采样，玻璃前景内容与静态环境背景分别独立重绘。常规材质按压和指针触发短暂高光，结束后没有持续动画；光学透镜采用独立滤镜。歌曲列表和歌词不叠加模糊。封面环境色通过低分辨率图片与 `ImageFiltered` 实现，不采样原生画面。

视频、扫码和管理端路由保持原生视图比例；页面过渡只淡入，弹层使用不透明表面，确认对话框不采样其背景。WebView 内部页面仍由 NAS 提供。

### 历史：全局三层设计系统

内容层不使用玻璃：连续歌曲列表、清晰原始封面、深蓝练唱卡、歌词和长文本依靠排版建立结构。搜索、快捷入口和表单使用标准玻璃；顶部工具栏、底部导航、迷你播放器和操作弹层使用悬浮透镜。不会为每一首歌创建滤镜或卡片。

`lib/app/tokens.dart` 是统一的几何与材质入口：

| Token | 用途 |
| --- | --- |
| `AppPalette` / `AppSurfaces` | 原有品牌蓝、录音红、雾银 / 午夜背景、克制的蓝色环境光、分组底色、反射、深蓝内容卡 |
| `AppSpace` | 4 / 8 / 12 / 16 / 24 / 28 / 32dp；页面边距 24dp |
| `AppRadii` | 封面 12、普通控件 18、音乐 Banner 20、内容卡 24、悬浮玻璃 28dp |
| `AppSizes` | 普通触控 48、长辈 56、输入区 60、列表封面 52、最大内容宽 720dp |
| `GlassMaterialSpec` | `standard`、`search`、`shortcut`、`field`、`onColor`、`floating`、`player`、`sheet`、`stageControl`、`mediaOverlay`；可配置浅深染色、模糊、高光、阴影、折射和单独底色 |
| `singVerseTheme.textTheme` | 系统字体，正文 16sp，主要标题 32sp；保留系统字号与长辈模式 |
| `AppMotion` / `AppMotionScope` | Spring、时长、手势反馈及普通 / 简化 / 关闭三档策略 |

复用关系：`GlassSurface` / `Glass` 统一材质；`GlassToolbar` 统一扫码 / 设置工具栏；`GlassField` 与 `GlassSearchField` 统一输入焦点；`AppSegments(liquid: true)` 统一滑动选择；`MiniPlayer` 在主框架与次级页面共用；`showAppSheet` 统一弹层。底部导航沿用主框架的状态与回调，仅更换同一套悬浮材质，不增加内部选中胶囊。

NAS、点歌、常唱、作品、设置、练唱详情、歌手、分类与家庭歌单直接导入 `app/design.dart` 即可复用这些组件。已有共享工具栏、弹层与播放器随材质入口同步更新；没有为每个页面复制一份玻璃绘制代码。视频、相机、WebView 的原生 Surface 仍保持稳定、不透明的专用保护路径。

点歌页保持原搜索控制器、350ms 防抖、筛选请求、收藏调用和练唱入口。推荐卡沿用第一首实际曲目与封面，不预设标题或更换封面。歌曲行连续排布，底部内容空间读取 Scaffold 实际传入的悬浮控件高度；键盘出现时立即隐藏迷你播放器，避免挤压搜索结果。

#### 第四轮推荐卡与局部精修

2026-11-17 保留既有页面结构，将练唱推荐改为更紧凑的音乐 Banner：16dp 内边距、20dp 外圆角；文字与原封面分列并垂直平衡，封面保持方形、12dp 圆角，按可用宽度使用 88 / 96dp。下方白色主按钮的可见高度 40dp、圆角 12dp，触控范围仍至少 48dp。收藏改为无描边的低浓度半透明圆形，视觉直径 40dp、触控范围 48dp，与封面居中对齐；收藏状态淡入和原调用保持不变。两项操作都继承原有按压反馈、禁用条件和动效偏好。深蓝渐变使用静态色阶与克制阴影，没有波浪或常驻发光动画。

搜索与快捷入口使用各自的轻标准材质，搜索增加底色区分和文字 / 图标对比，快捷入口降低高光、统一高度并调整图文间距。顶部工具栏减淡分隔线；悬浮材质降低白色染色和阴影，并略微下调浅色透射亮度，保留之前的局部对比压缩与窄边缘折射，不增加模糊。歌曲行只微调分隔线、垂直间距与两个操作图标的尺寸，封面、顺序及回调保持原样。

普通模式底部 Tab 收紧内边距与按钮高度，仍保留至少 48dp 点击区域；长辈模式继续使用较大控件。迷你播放器在其上方单独布局，保留 10dp 间隔、原有安全区与全部播放状态。All Night 只出现在隔离截图 fixture 中，正式应用始终读取实际 `state.current`，没有为了截图注入歌曲。

新增回归覆盖浅深色、320 / 390 / 430 / 768dp、100% / 130% / 200% 字号下的长标题、原封面标识和点击区域，验证收藏不会开启播放、按钮边缘点击只触发一次播放打开，以及收藏过渡中启用性能模式。实际设备截图与回归结果保存在 `build/reports/liquid-glass-refinement-v5/`。

#### 深色练唱控制台

2026-11-17 将「正在练唱」升级为深色控制台，使用共享 `AppPalette.stage*` 定义深蓝黑舞台、柔白正文、灰蓝辅助文字及浅蓝选中态。录音仍使用 `AppPalette.recording`。共享 `AppEnvironment` 只提供静态、低亮度的蓝色环境光，原封面环境色继续使用 `ImageFiltered`，没有新增常驻背景动画。

顶部采用对称的玻璃图标按钮与居中标题；歌曲名称 28sp、两行省略，歌手独立一行，收藏为蓝色状态与轻量图标过渡。视频保留 `videoAspect` 的真实比例、原生 FIT 与全屏逻辑，圆角 12dp。右下全屏按钮复用 `Glass` 的边缘与触摸光，使用 `mediaOverlay`：模糊为 0、无折射，绘制时直接跳过 BackdropFilter，原生视频不进入采样。

音轨分段与四列工具栏复用 `Glass` / `AppSegments`，使用 `stageControl` 的低浓度深色染色、3dp 局部散射和弱边缘高光，位于原生视频范围之外。选中块仍使用全局 340ms Spring；角色标记、不可用提示及录音锁定条件保持原样。暂停按钮从 64dp 收至 56dp；工具栏每列至少 48dp，不为单项增加卡片。录音主按钮从 58dp 收至 54dp、圆角 18dp，复用 `glossyActionLayer` 与全局按压反馈；长辈模式仍至少 56dp。

进度轨道为 3dp，滑块默认半径 5dp、拖动时轻放大到 7dp，触控高度至少 48dp；减少动态效果与性能模式关闭放大和滑块外层动画。进度跳转回调、选段标记和时间同步保持不变。时间使用等宽数字。练唱与录音状态左右分列，计时只读取原生 `recordedMs`；录音按钮同时显示实际计时。原生没有可恢复的“暂停录音”阶段，中断仍按既有契约结束并保留片段，不新增伪状态。

进度、歌词与录音计时分别监听现有 `state.playback`；页面结构只监听 `AppState`，音量过载提示变化另行触发布局更新。100ms 原生时钟事件不再重建标题、音轨控件及主按钮，原生采集和进度发布频率保持不变。回归同时检查歌词时间、按钮计时以及过载提示出现 / 消失，避免局部刷新导致状态停滞。

竖屏取消固定控制区高度与均分留白，改为自然高度和 12dp 模块间距，主要操作停留在底部安全区；视频与独立歌词的高度预算跟随真实字体排版。小屏、200% 字号、长辈及横屏继续使用原有滚动与安全布局，不挤掉主要操作。弹层继续复用 `showAppSheet` / `showAppDialog`，视频路由的浮层保持原生 Surface 保护。透明工具栏根据主题显式设置状态栏明暗，扫描场景的深色实底优先按实际背景设置，保证从深色练唱进入浅色回听后状态栏仍清晰。

新增回归覆盖真实 Flutter View 尺寸、40 组手机 / 平板横竖屏与大字号组合、触控范围、视频按钮无采样、录音计时与控件锁定，以及拖动只发送一次准确 seek。`integration_test/player_console_test.dart` 使用一次性 NAS、自制真实媒体和实际 Media3 / AndroidView / AudioRecord / AAC 流程，覆盖全屏返回、收藏、调音、音轨角色、重唱、选段、更多、系统字号、性能 / 透明度偏好、录音与回听。

物理机验收命令（先启动 `127.0.0.1:18181` 的独立 NAS / compute 并导入自制样本）：

```sh
python3 scripts/check-player-console.py \
  --device YOUR_DEVICE_SERIAL \
  --voice-sample /absolute/path/to/generated/voice-test.wav \
  --output build/reports/player-console-new-run
```

宿主驱动拒绝模拟器及已有报告目录，通过指定设备的 adb reverse 仅连接测试端口，权限授予只针对 `.e2e`。使用 `adb install -r` 覆盖安装，拒绝时立即停止，不采用 Flutter 的卸载重试；连接现有 VM 并保留测试包。为兼容 vivo 的进程日志限制，仅查找隔离包 UID 的本机监听端口，并验证 Dart VM 协议。系统字号和端口映射在 finally 中恢复，不清空应用数据或删除录音；采样前停止录屏。FrameTiming 使用 `benchmarkLive`，每场景预热后采样 20 秒，由框架与引擎自然调度，避免强制 pump 帧的等待时间干扰。输出真实设备截图、交互视频、逐项验收和三组原生播放 FrameTiming。录音样本保留在隔离包内，不替代真实歌曲音质、蓝牙或中断专项验收。

### 历史：动效策略

`AppMotionScope` 是 UI 策略入口，媒体时钟、歌词时间同步、网络请求与录音状态不依赖动画完成。

| 状态 | 界面动效 | 材质 |
| --- | --- | --- |
| 默认 | Spring、轻量淡入 / 位移与按压反馈 | 局部玻璃 |
| 系统 Reduce Motion / 辅助导航 | 取消位移、缩放、弹性与交错，必要淡入至多 100ms | 保留透明度偏好 |
| 长辈模式 | 简化反馈 | 不透明 |
| 高对比度 / 减少透明效果 | 遵循当前动态策略 | 不透明 |
| 性能模式 | 立即停止界面动画 | 无实时模糊，保留静态光影 |

长辈模式触控区域至少 56dp，普通模式至少 48dp。`performanceMode` 默认关闭，单独持久保存，切换时立即通知界面，不覆盖主题和透明度设置。

`AppMotion` 集中定义按下 100ms、恢复 220ms、导航 340ms、页面 320ms、弹层 360ms / 退出 220ms、展开 280ms。Spring 使用 Flutter 内置物理模型。内容仅前六项首次入场交错 24ms，PageStorage 保证滚动返回不重复入场。离屏标签页关闭 Ticker，保留页面和滚动状态。Android 预测返回继续使用 Flutter 原生手势处理。

共享弹层保留系统取消、返回、拖动和焦点行为。弹层动画控制器在路由退出 Overlay 后释放；中途开启性能模式会立即收束，避免残留遮罩。

### 历史：自动化验证

```sh
make check
make build
```

`test/app_motion_test.dart` 覆盖快速反向切换、稳定点击区域、禁用操作、Reduce Motion、原生视图背景策略、动画中开启性能模式、弹层取消、动画中返回和偏好隔离。现有业务回归继续覆盖 NAS 登录 / 身份隔离、收藏同步、录音保护、作品处理、电视登录及应用更新。

`test/mobile_redesign_test.dart` 的布局矩阵覆盖 320、375、390、430dp 手机与平板横竖屏，浅深色及 200% 字号，共 72 个主页面场景。主题测试检查正文、次要文字、品牌主按钮和标准材质在实际环境底色上的对比度至少 4.5:1。另有 24 组浅深色、尺寸和字号组合验证带播放器时的最后一首歌与操作按钮能够滚动到悬浮控件上方。

生成受控样本截图：

```sh
flutter --no-version-check test --no-pub test/mobile_redesign_test.dart \
  --plain-name 'capture refined' \
  --dart-define=CAPTURE_APP_UI=true \
  --dart-define=CAPTURE_PLAYER_UI=true \
  --dart-define=CAPTURE_NAS_UI=true \
  --dart-define=UI_ROUND=nas-form-refined
flutter --no-version-check test --no-pub test/mobile_redesign_test.dart \
  --plain-name 'liquid glass main pages adapt' \
  --dart-define=CAPTURE_GLASS_MATRIX=true
```

截图写入 `build/reports/mobile-ui-unslop/`、`build/reports/mobile-player-unslop/` 和 `build/reports/liquid-glass/matrix/`。截图测试使用可控封面、波形与数据，不能替代原生设备验收。

### 历史：Android profile 验收

用户已指定后续实测使用当前连接的物理机。2026-11-17 连接的设备为 vivo V2417A（Android 15，serial `YOUR_DEVICE_SERIAL`）；实测命令必须显式绑定该物理机，不再默认使用模拟器。使用独立 `.e2e` 包，不覆盖日常应用或触碰其账号、作品与录音。历史模拟器结果保留并明确标注来源。

沿用 README 中的独立 NAS 样本流程，服务必须使用新建临时数据目录和 `18181` 端口。为滚动场景提供足够的独立歌曲。只使用 `.e2e` 包；脚本拒绝连接日常 NAS。已有录音不允许被 profile 中断。

下面的模拟器命令仅保留历史复现说明；后续实测使用上方物理机命令。

```sh
python3 scripts/check-mobile-karaoke.py --suite profile \
  --device emulator-5554 \
  --voice-sample /absolute/path/to/generated/voice-test.wav \
  --output build/reports/liquid-glass/profile-new-run
```

输出目录必须全新，历史数据不被覆盖。profile 使用 `flutter drive --profile`，读取预热后的真实 `FrameTiming`，分别记录默认 / 性能模式下的导航、滚动、弹层、按压及原生播放歌词场景，输出 `frame-timings.json`、`integration.log`、截图和录屏。通过既有 NAS 数据 API 选定自制样本，在真实 `PlayerPage` 准备原生播放场景；准备和截图等待不计入帧采样窗口。日志逐场景输出，完整报告由 driver 写入文件，并校验十个场景齐全，避免 Android 日志截断误报。脚本的 `--suite flow` 与 `--suite visual` 保留原有流程。

60Hz 验收目标为 UI / Raster 各自 P95 ≤16.7ms、任一线程超预算的帧占比 <1%。报告必须注明设备、分辨率、渲染器、构建模式及采样数。软件渲染模拟器只能用于布局和行为检查；代表性真机数据才可用于 60 FPS 结论。真实麦克风、蓝牙、中断、相机扫码、WebView 登录和系统覆盖安装仍需设备验收。

### 历史：NAS 光学材质设备验证

```sh
ORG_GRADLE_PROJECT_singverseE2e=true \
SINGVERSE_NAS_GLASS_OUTPUT=build/reports/nas-liquid-optics-v2/android \
flutter --no-version-check drive --profile --no-pub --enable-impeller \
  --driver=test_driver/nas_glass_driver.dart \
  --target=integration_test/nas_glass_test.dart -d emulator-5554
```

仅使用隔离的 `.e2e` 包。该用例使用内存数据库、内存偏好、空密码库和受控曲目状态，不连接 NAS、不操作真实音频或凭据。它检查实际透镜渲染对象、浅深色、键盘焦点、减少透明效果、动画中切换性能模式以及播放数据保持。预热后记录默认 / 性能模式协议快速反向切换的真实 FrameTiming，按 buildStart 剔除采样窗口之前的批量回调。帧统计只代表此场景和设备，不能替代真机 60 FPS 验收。

测试日志的 `NAS_GLASS_SCREEN:<name>` 标记供宿主机 `adb -s emulator-5554 exec-out screencap -p` 截图，避免 Android ImageView 截图转换对原生 Surface 与帧数据的影响。界面录屏须在帧采样前停止，镜像轮询也应暂停。

设计依据：Apple [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)；Flutter [Fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders)。SDK 能力以仓库当前 Flutter 3.47.5 的 `dart:ui` 源码为准。

### 历史：点歌设计系统 Android 验证

```sh
ORG_GRADLE_PROJECT_singverseE2e=true \
SINGVERSE_LIBRARY_GLASS_OUTPUT=build/reports/singverse-design-system-v3/android \
flutter --no-version-check drive --profile --no-pub --enable-impeller \
  --driver=test_driver/library_glass_driver.dart \
  --target=integration_test/library_glass_test.dart -d emulator-5554
```

该用例仅在 `.e2e` 隔离包使用受控曲库、内存偏好、内存数据库和测试方法通道，不替换正式客户端数据来源，不连接真实 NAS 或麦克风。验证实际 Impeller 透镜、浅深色、有播放器的列表末尾、键盘、搜索请求与结果、筛选弹层、收藏、播放暂停、详情、Tab 和设置入口；扫码入口可点击，实际摄像头识别继续列为设备验收项。宿主机在 `LIBRARY_GLASS_SCREEN` 标记截取原生画面，`LIBRARY_GLASS_SAMPLE` 前停止录屏和镜像，分别采集普通 / 性能模式滚动的 FrameTiming。连续手势逐帧移动并至少采集 100 帧，避免将只有两个绘制帧的瞬时拖动误作持续滚动性能。

24 组带播放器截图可通过 `--name 'floating library controls leave' --dart-define=CAPTURE_DESIGN_SYSTEM=true` 生成，位于 `build/reports/singverse-design-system-v3/matrix/`。这些是 Flutter 布局截图；与 Android 原生实拍分开展示，不能用来声称已验证系统原生 Liquid Glass 或真机 60 FPS。


### 历史：第三轮点歌材质精修（2026-11-17）

保留构图、业务回调及全部播放器条件。标准玻璃采用 3dp 模糊、单层 0.65dp 渐变边缘；卡片收藏采用 2dp 模糊和同一条细轮廓。悬浮导航 / 工具栏采用 4dp 模糊，播放器采用 5dp，均保留窄边缘折射和低强度反射。浮层减弱阴影；着色器抑制透出封面的饱和色，并按亮度保护前景对比度。背景移除波浪与紫色光团，仅保留浅灰白 / 午夜底色和极淡蓝光。收藏图标使用轻量淡入，遵循减少动态效果和性能模式。

播放器没有被删除：`AppShell` 在存在 `state.current` 且键盘收起时显示；其他支持路由由应用层展示，避免重复。旧主图的截图样本没有当前歌曲，旧 NAS 截图才注入 All Night，因此两张预览状态不一致。本轮主预览和 Android 隔离验证均使用带封面的 All Night 测试状态，正式应用没有加入预设歌曲或改变播放状态管理。新增像素回归以黑白背景验证降级玻璃压低背景对比度且不改变前景品牌色；另检查初始空状态、播放状态稍后恢复、快速 Tab 切换、键盘隐藏 / 恢复、材质偏好变化和单次播放 / 暂停调用。

通过 `--dart-define=DESIGN_ROUND=liquid-glass-refinement-v4` 将 24 组适配截图写入独立目录，保留上一轮截图。原生截图、前后对比、录屏、帧数据与测试报告位于 `build/reports/liquid-glass-refinement-v4/`。

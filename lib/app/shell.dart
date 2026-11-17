import 'dart:async';

import '../features/updates/update_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../features/admin/admin_page.dart';
import '../features/library/connection.dart';
import '../features/library/library_pages.dart';
import '../features/library/widgets.dart';
import '../features/singing/works_page.dart';
import '../features/tv_control/tv_page.dart';
import 'design.dart';
import 'mini_player.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});
  final AppState state;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  final backdrop = BackdropKey();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final drafts = state.visibleWorks
          .where((w) => w['status'] != 'SAVED' && w['status'] != 'MISSING')
          .length;
      final largeToolbar = MediaQuery.textScalerOf(context).scale(16) > 22;
      final shell = PopScope(
        canPop: tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => tab = 0);
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            titleSpacing: AppSpace.page,
            backgroundColor: Colors.transparent,
            systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            toolbarHeight: state.senior
                ? (MediaQuery.textScalerOf(context).scale(34) * 1.18 + 24)
                      .clamp(76, 156)
                : (MediaQuery.textScalerOf(context).scale(32) * 1.18 +
                          MediaQuery.textScalerOf(context).scale(12) * 1.3 +
                          28)
                      .clamp(88, 156),
            automaticallyImplyLeading: false,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!state.senior) ...[
                  Text(
                    'SingVerse',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  const ['点歌', '常唱', '作品'][tab],
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ],
            ),
            actions: [
              if (!state.senior)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GlassToolbar(
                    state: state,
                    children: [
                      IconButton(
                        key: const Key('open-tv'),
                        tooltip: '扫一扫',
                        onPressed: () => openTv(context, state),
                        icon: const Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 21,
                        ),
                      ),
                      IconButton(
                        key: const Key('open-settings'),
                        tooltip: '设置',
                        onPressed: () => openSettings(context, state),
                        icon: const Icon(Icons.settings_outlined, size: 21),
                      ),
                    ],
                  ),
                ),
              if (state.senior && largeToolbar)
                TextButton(
                  key: const Key('open-tv'),
                  style: TextButton.styleFrom(
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(inherit: true, fontSize: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => openTv(context, state),
                  child: const Text('扫码'),
                )
              else if (state.senior)
                TextButton.icon(
                  key: const Key('open-tv'),
                  onPressed: () => openTv(context, state),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('扫码'),
                ),
              if (state.senior && largeToolbar)
                TextButton(
                  key: const Key('open-settings'),
                  style: TextButton.styleFrom(
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(inherit: true, fontSize: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => openSettings(context, state),
                  child: const Text('设置'),
                )
              else if (state.senior)
                TextButton.icon(
                  key: const Key('open-settings'),
                  onPressed: () => openSettings(context, state),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('设置'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: ContentWidth(
              child: IndexedStack(
                index: tab,
                children: [
                  TickerMode(
                    enabled: tab == 0,
                    child: MotionTabPane(
                      active: tab == 0,
                      child: state.authenticated
                          ? SongsPage(
                              key: ValueKey(state.instanceId),
                              state: state,
                              embedded: true,
                              showBrowse: true,
                            )
                          : _Disconnected(
                              state: state,
                              onOpenWorks: () => setState(() => tab = 2),
                            ),
                    ),
                  ),
                  TickerMode(
                    enabled: tab == 1,
                    child: MotionTabPane(
                      active: tab == 1,
                      child: FrequentPage(
                        key: ValueKey('personal:${state.instanceId}'),
                        state: state,
                      ),
                    ),
                  ),
                  TickerMode(
                    enabled: tab == 2,
                    child: MotionTabPane(
                      active: tab == 2,
                      child: WorksPage(state: state, embedded: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: ContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  0,
                  AppSpace.page,
                  AppSpace.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MotionVisibility(
                      visible:
                          state.current != null &&
                          MediaQuery.viewInsetsOf(context).bottom == 0,
                      immediate: MediaQuery.viewInsetsOf(context).bottom > 0,
                      child: MiniPlayer(state: state, inset: false),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: state.senior ? AppSizes.contentWidth : 360,
                      ),
                      child: Glass(
                        state: state,
                        radius: AppRadii.floating,
                        variant: GlassVariant.liquid,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Row(
                            children: [
                              for (final entry in [
                                (
                                  0,
                                  Icons.library_music_outlined,
                                  '点歌',
                                  'nav-songs',
                                ),
                                (
                                  1,
                                  Icons.favorite_outline_rounded,
                                  '常唱',
                                  'nav-frequent',
                                ),
                                (
                                  2,
                                  Icons.graphic_eq_rounded,
                                  '作品',
                                  'nav-works',
                                ),
                              ])
                                Expanded(
                                  child: Semantics(
                                    selected: tab == entry.$1,
                                    child: TextButton(
                                      key: Key(entry.$4),
                                      style: TextButton.styleFrom(
                                        minimumSize: Size(
                                          56,
                                          state.senior ? 64 : 48,
                                        ),
                                        foregroundColor: tab == entry.$1
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        padding: EdgeInsets.symmetric(
                                          vertical: state.senior ? 6 : 4,
                                        ),
                                      ),
                                      onPressed: () {
                                        if (tab != entry.$1 &&
                                            !state.taking &&
                                            AppMotionScope.levelOf(context) ==
                                                AppMotionLevel.full) {
                                          unawaited(
                                            HapticFeedback.selectionClick(),
                                          );
                                        }
                                        setState(() => tab = entry.$1);
                                        if (entry.$1 == 1) {
                                          unawaited(state.refreshPersonal());
                                        }
                                      },
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Badge(
                                            isLabelVisible:
                                                entry.$1 == 2 && drafts > 0,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .secondaryContainer,
                                            textColor: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            label: Text('$drafts'),
                                            child: Icon(
                                              entry.$2,
                                              size: state.senior ? 28 : 24,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            entry.$3,
                                            style: TextStyle(
                                              fontSize: state.senior ? 18 : 12,
                                              fontWeight: tab == entry.$1
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      // Standard controls share only non-overlapping clips. Optical floating
      // layers own their filter because each samples a different background.
      return AppEnvironment(
        child: BackdropGroup(backdropKey: backdrop, child: shell),
      );
    },
  );
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.state, required this.onOpenWorks});
  final AppState state;
  final VoidCallback onOpenWorks;
  @override
  Widget build(BuildContext context) {
    final material = AppSurfaces.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (state.error != null) Notice(state.error!),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: material.spotlight,
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  material.onSpotlight.withValues(alpha: .07),
                  material.spotlight,
                ),
                material.spotlight,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: material.onSpotlight.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.library_music_outlined,
                    size: 32,
                    color: material.onSpotlight,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                state.origin.isEmpty ? '连接家庭曲库' : '重新连接家庭曲库',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(color: material.onSpotlight),
              ),
              const SizedBox(height: 12),
              Text(
                '从 NAS 选歌练唱，录音保存在手机。已保存的作品可以离线回听。',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: material.spotlightMuted),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: material.onSpotlight,
                  foregroundColor: material.spotlight,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => openConnection(context, state),
                icon: const Icon(Icons.link_rounded),
                label: Text(state.origin.isEmpty ? '连接 NAS' : '重新登录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onOpenWorks,
          icon: const Icon(Icons.headphones_rounded, size: 21),
          label: const Text('查看本机作品'),
        ),
      ],
    );
  }
}

class FrequentPage extends StatefulWidget {
  const FrequentPage({super.key, required this.state});
  final AppState state;
  @override
  State<FrequentPage> createState() => _FrequentPageState();
}

class _FrequentPageState extends State<FrequentPage> {
  bool history = false;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> clear() async {
    final yes = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空最近练唱？'),
        content: const Text('只清除此 NAS 在手机上的记录，不影响收藏和作品。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空记录'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await uiTask(context, () async {
        await widget.state.store.clearHistory(widget.state.instanceId);
        await widget.state.refreshPersonal();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final rows = (history ? state.history : state.favorites)
        .where(
          (s) => '${s.title} ${s.artist}'.toLowerCase().contains(
            search.text.toLowerCase(),
          ),
        )
        .toList();
    return CustomScrollView(
      key: PageStorageKey('personal-scroll:${state.instanceId}'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: history ? '搜索最近练唱' : '搜索收藏歌曲',
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () => setState(search.clear),
                            icon: const Icon(Icons.cancel_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                AppSegments<bool>(
                  values: const [(false, '收藏'), (true, '最近练唱')],
                  selected: history,
                  senior: state.senior,
                  onChanged: (value) => setState(() => history = value),
                ),
                if (search.text.isEmpty && !state.senior) ...[
                  const SizedBox(height: 20),
                  _CollectionCover(
                    state: state,
                    history: history,
                    songs: history ? state.history : state.favorites,
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                  child: SectionTitle(
                    history ? '最近练唱' : 'NAS 共享收藏',
                    trailing: history && state.history.isNotEmpty
                        ? TextButton(onPressed: clear, child: const Text('清空'))
                        : Text(
                            !history && !state.favoritesReady
                                ? '待读取'
                                : '${history ? state.history.length : state.favorites.length} 首',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                  ),
                ),
                if (!history) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '后台、手机和电视同步',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: '刷新收藏',
                        onPressed:
                            state.favoritesLoading || state.favoriteSaving
                            ? null
                            : () => state.refreshFavorites(),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (state.favoritesLoading) const LinearProgressIndicator(),
                  if (state.favoritesError != null)
                    Notice('收藏读取失败：${state.favoritesError}。当前内容可能尚未更新。'),
                  if (!state.authenticated)
                    const Notice('连接 NAS 并登录后读取共享收藏。练唱记录仍可在本机查看。'),
                ],
                if (rows.isEmpty &&
                    (history ||
                        (state.authenticated &&
                            state.favoritesReady &&
                            !state.favoritesLoading &&
                            state.favoritesError == null)))
                  Notice(
                    search.text.isNotEmpty
                        ? '没有匹配的歌曲，试试其他关键词。'
                        : history
                        ? '唱过的歌曲会出现在这里。'
                        : '还没有收藏。点歌曲旁的爱心，就能在这里快速找到。',
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => MotionEntrance(
              key: ValueKey('personal:${state.instanceId}:${rows[index].id}'),
              index: index,
              child: SongRow(state: state, song: rows[index]),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverToBoxAdapter(child: Column(children: [])),
        ),
      ],
    );
  }
}

class _CollectionCover extends StatelessWidget {
  const _CollectionCover({
    required this.state,
    required this.history,
    required this.songs,
  });
  final AppState state;
  final bool history;
  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final large = MediaQuery.textScalerOf(context).scale(16) > 21;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .45),
          width: .5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  history ? Icons.history_rounded : Icons.favorite_rounded,
                  size: 21,
                  color: scheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  history ? '唱过，还想再唱' : '喜欢的，都在这里',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${songs.length} 首${history ? '练唱记录' : '收藏歌曲'}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!large && songs.isNotEmpty) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 112,
              height: 104,
              child: ExcludeSemantics(
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    for (
                      var index = songs.take(3).length - 1;
                      index >= 0;
                      index--
                    )
                      Positioned(
                        right: index * 8.0,
                        top: index * 5.0,
                        child: Transform.rotate(
                          angle: -index * .10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: scheme.surface,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppSurfaces.of(context).shadow,
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Artwork(
                              state: state,
                              path: songs[index].cover,
                              revision: songs[index].data['revision']
                                  ?.toString(),
                              size: 88,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void openSettings(BuildContext context, AppState state) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'settings'),
    builder: (_) => SettingsPage(state: state),
  ),
);

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      Widget group(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    children[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      Widget icon(IconData data) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(data, size: 20, color: scheme.primary),
      );
      return Scaffold(
        appBar: AppToolbar(title: const Text('设置')),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              group('家庭曲库', [
                ListTile(
                  leading: icon(Icons.dns_outlined),
                  title: const Text('NAS 连接与账号'),
                  subtitle: Text(
                    state.authenticated
                        ? '${state.accountName.isEmpty ? '已登录' : state.accountName}\n${state.origin}'
                        : state.origin.isEmpty
                        ? '尚未连接'
                        : '需要登录\n${state.origin}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openConnection(context, state),
                ),
                ListTile(
                  key: const Key('open-admin'),
                  leading: icon(Icons.tune_rounded),
                  title: const Text('管理端'),
                  subtitle: Text(
                    state.origin.isEmpty
                        ? '连接 NAS 后管理曲库和系统设置'
                        : '管理当前 NAS 的曲库和系统设置',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openAdmin(context, state),
                ),
                ListenableBuilder(
                  listenable: state.updates,
                  builder: (context, _) => ListTile(
                    leading: icon(Icons.system_update_outlined),
                    title: const Text('应用更新'),
                    subtitle: Text(state.updates.status),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: 'updates'),
                        builder: (_) => UpdatePage(updates: state.updates),
                      ),
                    ),
                  ),
                ),
              ]),
              group('外观', [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: AppSegments<ThemeMode>(
                    values: const [
                      (ThemeMode.system, '跟随系统'),
                      (ThemeMode.light, '浅色'),
                      (ThemeMode.dark, '深色'),
                    ],
                    selected: state.themeMode,
                    senior: state.senior,
                    onChanged: (value) =>
                        uiTask(context, () => state.setTheme(value)),
                  ),
                ),
                SwitchListTile(
                  value: state.reduceTransparency,
                  onChanged: (value) =>
                      uiTask(context, () => state.setTransparency(value)),
                  title: const Text('减少透明效果'),
                  subtitle: Text(
                    state.senior ? '长辈模式始终使用清晰的不透明背景' : '提高导航和播放器的背景清晰度',
                  ),
                ),
              ]),
              group('使用体验', [
                SwitchListTile(
                  value: state.senior,
                  onChanged: (value) => uiTask(
                    context,
                    () => state.setUiMode(
                      value ? UiMode.senior : UiMode.standard,
                    ),
                  ),
                  title: Text(state.senior ? '长辈模式已开启' : '长辈模式'),
                  subtitle: const Text('放大文字和按钮，主导航位置保持不变'),
                ),
                SwitchListTile(
                  key: const Key('performance-mode'),
                  value: state.performanceMode,
                  onChanged: (value) =>
                      uiTask(context, () => state.setPerformanceMode(value)),
                  title: const Text('性能模式'),
                  subtitle: const Text('关闭界面动效和实时模糊，让较早的设备也能流畅使用'),
                ),
              ]),
              Text(
                '歌曲与收藏来自 NAS，后台、手机和电视共用收藏。练唱记录与录音作品保存在此手机。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (state.defaultPassword) const Notice('NAS 仍使用初始密码，请在管理端修改。'),
            ],
          ),
        ),
      );
    },
  );
}

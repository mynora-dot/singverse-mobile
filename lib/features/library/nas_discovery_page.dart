import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/design.dart';
import '../../core/nas_discovery.dart';

class NasDiscoveryPage extends StatefulWidget {
  const NasDiscoveryPage({super.key, required this.discovery});
  final NasDiscovery discovery;
  @override
  State<NasDiscoveryPage> createState() => _NasDiscoveryPageState();
}

class _NasDiscoveryPageState extends State<NasDiscoveryPage>
    with WidgetsBindingObserver {
  NasDiscoverySnapshot snapshot = const NasDiscoverySnapshot(searching: true);
  StreamSubscription<NasDiscoverySnapshot>? subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = widget.discovery.snapshots.listen(
      (value) {
        if (mounted) setState(() => snapshot = value);
      },
      onError: (Object _) {
        if (mounted) {
          setState(
            () => snapshot = const NasDiscoverySnapshot(
              error: '无法查找局域网设备，请检查网络后重试',
            ),
          );
        }
      },
    );
    start();
  }

  Future<void> start() async {
    setState(() => snapshot = const NasDiscoverySnapshot(searching: true));
    try {
      await widget.discovery.start();
    } catch (_) {
      if (mounted) {
        setState(
          () => snapshot = const NasDiscoverySnapshot(
            error: '无法查找局域网设备，请检查网络后重试',
          ),
        );
      }
    }
  }

  Future<void> stop() async {
    try {
      await widget.discovery.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(subscription?.cancel());
    unawaited(stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return AppEnvironment(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppToolbar(
          leading: Navigator.canPop(context)
              ? Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
                  child: GlassSurface(
                    radius: 24,
                    variant: GlassVariant.liquid,
                    child: const BackButton(),
                  ),
                )
              : null,
          title: const Text('查找局域网 NAS'),
        ),
        body: SafeArea(
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      if (snapshot.searching) ...[
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          snapshot.searching
                              ? '正在扫描局域网设备…'
                              : snapshot.services.isEmpty
                              ? '未发现设备'
                              : '找到 ${snapshot.services.length} 台 NAS',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (snapshot.searching) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      color: AppPalette.brand,
                      backgroundColor: scheme.onSurface.withValues(alpha: .10),
                    ),
                  ),
                ],
                if (snapshot.error != null) ...[
                  const SizedBox(height: 14),
                  Notice(snapshot.error!, action: start),
                ],
                if (!snapshot.searching &&
                    snapshot.services.isEmpty &&
                    snapshot.error == null) ...[
                  const SizedBox(height: 14),
                  const Notice('请确认手机与 NAS 处于同一局域网'),
                ],
                if (snapshot.services.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  GlassSurface(
                    radius: 24,
                    material: GlassMaterialSpec.standard,
                    child: Column(
                      children: [
                        for (var i = 0; i < snapshot.services.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 64,
                              endIndent: 16,
                              color: scheme.onSurface.withValues(
                                alpha: dark ? .08 : .06,
                              ),
                            ),
                          ListTile(
                            key: ValueKey(
                              'discovered-nas:${snapshot.services[i].origin}',
                            ),
                            contentPadding: const EdgeInsets.fromLTRB(
                              16,
                              6,
                              12,
                              6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: i == 0
                                    ? const Radius.circular(24)
                                    : Radius.zero,
                                bottom: i == snapshot.services.length - 1
                                    ? const Radius.circular(24)
                                    : Radius.zero,
                              ),
                            ),
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [AppPalette.brand, AppPalette.coral],
                                ),
                              ),
                              child: const Icon(
                                Icons.dns_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              snapshot.services[i].name,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 15.5,
                              ),
                            ),
                            subtitle: Text(
                              snapshot.services[i].origin,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: .65,
                              ),
                            ),
                            onTap: () async {
                              final service = snapshot.services[i];
                              await stop();
                              if (context.mounted) {
                                Navigator.pop(context, service);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (!snapshot.searching) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppPalette.brand, AppPalette.brandDeep],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppPalette.brand.withValues(alpha: .32),
                          blurRadius: 20,
                          spreadRadius: -4,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: start,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('重新查找'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                MotionPress(
                  child: GlassSurface(
                    radius: 999,
                    material: GlassMaterialSpec.shortcut,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: Colors.transparent,
                        foregroundColor: scheme.onSurface,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('手动输入 IP 或域名'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

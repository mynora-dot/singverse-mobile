import 'package:flutter/material.dart';

import '../../app/design.dart';
import '../../core/login_store.dart';

class LoginHistoryPage extends StatefulWidget {
  const LoginHistoryPage({super.key, required this.store});
  final LoginStore store;
  @override
  State<LoginHistoryPage> createState() => _LoginHistoryPageState();
}

class _LoginHistoryPageState extends State<LoginHistoryPage> {
  List<LoginRecord> records = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.store.load();
      if (mounted) setState(() => records = value);
    } catch (_) {
      if (mounted) setState(() => error = '无法读取历史登录，请重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> manage(LoginRecord record, String action) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (action == 'remove') {
        await widget.store.remove(record);
      } else {
        await widget.store.forgetPassword(record);
      }
      if (mounted) await load();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '修改未完成，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final groups = <String, List<LoginRecord>>{};
    for (final record in records) {
      groups.putIfAbsent(record.instanceId, () => []).add(record);
    }
    return AppBackdropCapture(
      builder: (context, layerBackdrop) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppToolbar(
          leading: Navigator.canPop(context)
              ? AppBackdropScope(
                  backdrop: layerBackdrop,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
                    child: GlassSurface(
                      radius: 24,
                      variant: GlassVariant.liquid,
                      child: const BackButton(),
                    ),
                  ),
                )
              : null,
          title: const Text('历史登录'),
        ),
        body: AppBackdropSource(
          backdrop: layerBackdrop,
          child: AppEnvironment(
            child: SafeArea(
              child: ContentWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  children: [
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            color: AppPalette.brand,
                            backgroundColor: scheme.onSurface.withValues(
                              alpha: .10,
                            ),
                          ),
                        ),
                      ),
                    if (error != null) Notice(error!, action: load),
                    if (!loading && error == null && records.isEmpty)
                      const Notice('还没有历史登录'),
                    for (final group in groups.values) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Text(
                          group.first.name.isEmpty
                              ? 'SingVerse NAS'
                              : group.first.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      GlassSurface(
                        radius: 24,
                        material: GlassMaterialSpec.standard,
                        child: Column(
                          children: [
                            for (var i = 0; i < group.length; i++) ...[
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
                                key: ValueKey('login-record:${group[i].id}'),
                                contentPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  8,
                                  6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: i == 0
                                        ? const Radius.circular(24)
                                        : Radius.zero,
                                    bottom: i == group.length - 1
                                        ? const Radius.circular(24)
                                        : Radius.zero,
                                  ),
                                ),
                                enabled: !loading,
                                leading: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppPalette.brand,
                                        AppPalette.coral,
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.dns_rounded,
                                    size: 19,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  group[i].username,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.5,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group[i].address,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${group[i].protocol} · ${group[i].hasPassword ? '已记住密码' : '需输入密码'}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant
                                                  .withValues(alpha: .78),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: loading
                                    ? null
                                    : () => Navigator.pop(context, group[i]),
                                trailing: PopupMenuButton<String>(
                                  tooltip: '管理 ${group[i].username} 的登录记录',
                                  enabled: !loading,
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  elevation: 10,
                                  onSelected: (action) =>
                                      manage(group[i], action),
                                  itemBuilder: (_) => [
                                    if (group[i].hasPassword)
                                      PopupMenuItem(
                                        value: 'forget',
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.key_off_rounded,
                                              size: 18,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 10),
                                            const Text('忘记已保存密码'),
                                          ],
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: scheme.error,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '移除登录记录',
                                            style: TextStyle(
                                              color: scheme.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

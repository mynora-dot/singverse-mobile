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
    final groups = <String, List<LoginRecord>>{};
    for (final record in records) {
      groups.putIfAbsent(record.instanceId, () => []).add(record);
    }
    return Scaffold(
      appBar: AppToolbar(title: const Text('历史登录')),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('选择记录回填地址和账号，点击登录后连接。'),
              const SizedBox(height: 24),
              if (loading) const LinearProgressIndicator(),
              if (error != null) Notice(error!, action: load),
              if (!loading && error == null && records.isEmpty)
                const Notice('还没有历史登录\n成功登录后，设备和账号会保存在这里'),
              for (final group in groups.values) ...[
                SectionTitle(
                  group.first.name.isEmpty ? 'SingVerse NAS' : group.first.name,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < group.length; i++) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          key: ValueKey('login-record:${group[i].id}'),
                          enabled: !loading,
                          title: Text(group[i].username),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(group[i].address),
                                const SizedBox(height: 4),
                                Text(
                                  '${group[i].protocol} · ${group[i].hasPassword ? '已记住密码' : '需输入密码'}',
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
                            onSelected: (action) => manage(group[i], action),
                            itemBuilder: (_) => [
                              if (group[i].hasPassword)
                                const PopupMenuItem(
                                  value: 'forget',
                                  child: Text('忘记已保存密码'),
                                ),
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('移除登录记录'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

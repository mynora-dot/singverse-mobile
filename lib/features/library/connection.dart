import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/design.dart';
import '../../core/app_state.dart';
import '../../core/login_store.dart';
import '../../core/nas_discovery.dart';
import 'login_history_page.dart';
import 'nas_discovery_page.dart';
import 'password_reset_page.dart';

Future<void> openConnection(BuildContext context, AppState state) async {
  if (state.taking || state.singingPhase == 'RENDERING') {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先结束录音或等待混音完成，再修改 NAS 连接。')));
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'connection'),
      builder: (_) => ConnectionPage(state: state),
    ),
  );
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.state,
    this.loginStore,
    this.discovery,
  });
  final AppState state;
  final LoginStore? loginStore;
  final NasDiscovery? discovery;
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final address = TextEditingController();
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  final code = TextEditingController();
  late final vault = widget.loginStore ?? NativeLoginStore();
  bool editing = false, checked = false, localBusy = false;
  bool remember = false, visible = false, useSavedPassword = false;
  String scheme = 'http';
  String? notice;
  int formRevision = 0;
  LoginRecord? selected, pendingLogin;
  String? pendingPassword;
  bool get locked =>
      widget.state.taking || widget.state.singingPhase == 'RENDERING';
  bool get working => widget.state.busy || localBusy || locked;

  @override
  void initState() {
    super.initState();
    editing = widget.state.origin.isEmpty;
    fillAddress(widget.state.origin);
    if (widget.state.accountName.isNotEmpty) {
      username.text = widget.state.accountName;
    }
    if (!widget.state.authenticated) loadRecent();
  }

  void fillAddress(String origin) {
    if (origin.isEmpty) return;
    final uri = Uri.parse(origin);
    scheme = uri.scheme;
    address.text = uri.authority;
  }

  Future<void> loadRecent() async {
    final revision = formRevision;
    try {
      final records = await vault.load();
      if (!mounted || working || revision != formRevision || records.isEmpty) {
        return;
      }
      final origin = widget.state.origin;
      final record = records.where((item) => item.origin == origin).firstOrNull;
      if (record != null || origin.isEmpty) {
        applyRecord(record ?? records.first);
      }
    } on PlatformException {
      // Login remains usable if the vault is unavailable; history offers retry.
    } on MissingPluginException {
      // Non-Android previews have no native vault.
    } catch (_) {
      if (mounted) setState(() => notice = '暂时无法读取历史登录，可手动输入或稍后重试');
    }
  }

  void applyRecord(LoginRecord record) {
    setState(() {
      formRevision++;
      editing = true;
      selected = record;
      fillAddress(record.origin);
      username.text = record.username;
      password.clear();
      remember = record.hasPassword;
      useSavedPassword = record.hasPassword;
      pendingLogin = null;
      pendingPassword = null;
      notice = null;
    });
  }

  void invalidateSaved() {
    formRevision++;
    selected = null;
    useSavedPassword = false;
    password.clear();
  }

  @override
  void dispose() {
    pendingPassword = null;
    address.dispose();
    username.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> finish(LoginRecord? record, String? secret) async {
    pendingPassword = null;
    pendingLogin = null;
    password.clear();
    code.clear();
    if (record != null) {
      try {
        await vault.save(record, password: secret);
      } catch (_) {
        if (mounted) setState(() => notice = '已登录，但未能保存历史登录，请稍后重试');
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> submit() async {
    if (working) return;
    setState(() {
      formRevision++;
      localBusy = true;
      notice = null;
    });
    final state = widget.state;
    try {
      if (state.mfaRequired) {
        if (code.text.trim().isEmpty) throw const FormatException('请输入动态码或恢复码');
        await state.verify(code.text.trim());
        code.clear();
        if (state.authenticated) await finish(pendingLogin, pendingPassword);
        return;
      }
      final next = connectionOrigin(address.text, scheme);
      final account = username.text.trim();
      if (account.isEmpty) throw const FormatException('请输入管理员账号');
      await state.connect(next);
      if (!mounted || state.error != null) return;
      final saved = selected;
      String? secret;
      if (useSavedPassword) {
        if (saved == null ||
            saved.origin != state.origin ||
            saved.instanceId != state.instanceId ||
            saved.username != account) {
          setState(() {
            useSavedPassword = false;
            selected = null;
          });
          throw const FormatException('此地址的曲库身份已变化，请重新输入密码');
        }
        secret = await vault.password(saved);
      }
      if (!mounted) return;
      final record = LoginRecord(
        origin: state.origin,
        instanceId: state.instanceId,
        username: account,
        name: state.serverName.isEmpty
            ? Uri.parse(state.origin).host
            : state.serverName,
        lastUsed: DateTime.now().millisecondsSinceEpoch,
      );
      if (state.authenticated && state.accountName == account) {
        await finish(record, remember ? secret : null);
        return;
      }
      secret = useSavedPassword ? secret : password.text;
      if (secret == null || secret.isEmpty) {
        setState(() => useSavedPassword = false);
        throw const FormatException('请输入密码');
      }
      if (state.authenticated) await state.logout();
      if (!mounted) return;
      pendingLogin = record;
      pendingPassword = remember ? secret : null;
      await state.login(secret, username: account);
      if (!mounted) return;
      if (state.authenticated) {
        await finish(record, pendingPassword);
      } else if (state.mfaRequired) {
        password.clear();
      } else {
        pendingLogin = null;
        pendingPassword = null;
      }
    } catch (error) {
      if (mounted) setState(() => notice = connectionError(error));
    } finally {
      if (mounted) setState(() => localBusy = false);
    }
  }

  Future<void> changeRemember(bool value) async {
    if (working) return;
    final record = selected;
    if (value || record == null || !record.hasPassword) {
      setState(() => remember = value);
      return;
    }
    setState(() => localBusy = true);
    try {
      await vault.forgetPassword(record);
      if (mounted) {
        setState(() {
          remember = false;
          useSavedPassword = false;
          selected = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => notice = connectionError(error));
    } finally {
      if (mounted) setState(() => localBusy = false);
    }
  }

  Future<void> showHistory() async {
    if (working) return;
    formRevision++;
    final record = await Navigator.push<LoginRecord>(
      context,
      MaterialPageRoute(builder: (_) => LoginHistoryPage(store: vault)),
    );
    if (!mounted) return;
    if (record != null) {
      applyRecord(record);
    } else if (selected != null) {
      final id = selected!.id;
      try {
        final records = await vault.load();
        if (!mounted || selected?.id != id) return;
        final current = records.where((item) => item.id == id).firstOrNull;
        if (current?.hasPassword != true) {
          setState(() {
            selected = current;
            useSavedPassword = false;
            remember = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => notice = '暂时无法读取历史登录，请稍后重试');
      }
    }
  }

  Future<void> discover() async {
    if (working) return;
    formRevision++;
    final service = await Navigator.push<DiscoveredNas>(
      context,
      MaterialPageRoute(
        builder: (_) => NasDiscoveryPage(
          discovery: widget.discovery ?? NativeNasDiscovery(),
        ),
      ),
    );
    if (mounted && service != null) {
      setState(() {
        invalidateSaved();
        fillAddress(service.origin);
        editing = true;
        notice = '已选择 ${service.name}，登录时将检查曲库身份';
      });
    }
  }

  Future<void> forgotPassword() async {
    if (working) return;
    setState(() {
      formRevision++;
      localBusy = true;
      notice = null;
    });
    try {
      await widget.state.connect(connectionOrigin(address.text, scheme));
      if (!mounted || widget.state.error != null) return;
      final reset = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => PasswordResetPage(
            state: widget.state,
            store: vault,
            username: username.text.trim(),
          ),
        ),
      );
      if (!mounted || reset == null) return;
      setState(() {
        username.text = reset;
        password.clear();
        code.clear();
        selected = null;
        useSavedPassword = false;
        pendingPassword = null;
        pendingLogin = null;
        notice = '密码已重置，请使用新密码登录';
      });
    } catch (error) {
      if (mounted) setState(() => notice = connectionError(error));
    } finally {
      if (mounted) setState(() => localBusy = false);
    }
  }

  Future<void> logout() async {
    if (working) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出 NAS 登录？'),
        content: const Text('本机播放将停止。收藏、练唱记录和录音作品仍保留在手机上。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await uiTask(context, widget.state.logout);
      if (mounted) {
        password.clear();
        code.clear();
        await loadRecent();
      }
    }
  }

  Widget detail(String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (context, size) {
        final caption = Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
        if (widget.state.senior ||
            MediaQuery.textScalerOf(context).scale(16) > 22 ||
            size.maxWidth < 280) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [caption, const SizedBox(height: 8), value],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 80, child: caption),
            const SizedBox(width: 12),
            Expanded(child: value),
          ],
        );
      },
    ),
  );

  Widget management(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? action,
  ) => ListTile(
    minTileHeight: widget.state.senior ? 88 : 72,
    leading: Icon(icon, size: 20),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
    onTap: action,
  );

  Widget loginForm(AppState state) {
    final theme = Theme.of(context);
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        key: const ValueKey('nas-account-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('连接你的家庭曲库', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '连接 NAS，选歌练唱。作品保存在此手机。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text('连接协议', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const ValueKey('nas-protocol'),
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            segments: const [
              ButtonSegment(value: 'http', label: Text('HTTP')),
              ButtonSegment(value: 'https', label: Text('HTTPS')),
            ],
            selected: {scheme},
            onSelectionChanged: working
                ? null
                : (values) => setState(() {
                    invalidateSaved();
                    scheme = values.first;
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('nas-address-field'),
            controller: address,
            enabled: !working,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'NAS 地址',
              hintText: '192.168.1.10:18080',
              prefixText: '$scheme://',
              suffixIcon: IconButton(
                key: const ValueKey('nas-history'),
                tooltip: '历史登录',
                onPressed: working ? null : showHistory,
                icon: const Icon(Icons.history_rounded, size: 20),
              ),
            ),
            onChanged: (value) => setState(() {
              invalidateSaved();
              final match = RegExp(
                r'^(https?)://',
                caseSensitive: false,
              ).firstMatch(value);
              if (match != null) {
                scheme = match[1]!.toLowerCase();
                address.text = value.substring(match.end);
                address.selection = TextSelection.collapsed(
                  offset: address.text.length,
                );
              }
            }),
          ),
          const SizedBox(height: 8),
          Text(
            scheme == 'https'
                ? '使用 NAS 配置的 HTTPS 端口和可信证书'
                : '填写 NAS 的实际 HTTP 端口，例如 18080',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('nas-username-field'),
            controller: username,
            enabled: !working,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '管理员账号'),
            onChanged: (_) => setState(invalidateSaved),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('nas-password-field'),
            controller: password,
            enabled: !working,
            obscureText: !visible,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: remember ? const [AutofillHints.password] : null,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              labelText: useSavedPassword ? '已保存密码' : '密码',
              hintText: useSavedPassword ? '已保存密码，登录时自动填入' : '输入 NAS 账号密码',
              suffixIcon: IconButton(
                tooltip: visible ? '隐藏密码' : '显示密码',
                onPressed: working
                    ? null
                    : () => setState(() => visible = !visible),
                icon: Icon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              ),
            ),
            onChanged: (_) => setState(() {
              formRevision++;
              useSavedPassword = false;
            }),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MergeSemantics(
                child: InkWell(
                  onTap: working ? null : () => changeRemember(!remember),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const ValueKey('remember-password'),
                        value: remember,
                        onChanged: working
                            ? null
                            : (value) => changeRemember(value ?? false),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text('记住密码'),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('forgot-password'),
                onPressed: working ? null : forgotPassword,
                child: const Text('忘记密码？'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('nas-submit'),
            onPressed: working ? null : submit,
            child: Text(working ? '正在连接…' : '登录并连接'),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('nas-discover'),
                onPressed: working ? null : discover,
                icon: const Icon(Icons.radar_rounded, size: 20),
                label: const Text('查找局域网 NAS'),
              ),
              TextButton.icon(
                onPressed: working ? null : showHistory,
                icon: const Icon(Icons.history_rounded, size: 20),
                label: const Text('历史登录'),
              ),
            ],
          ),
          if (editing && state.authenticated)
            TextButton(
              onPressed: working
                  ? null
                  : () => setState(() {
                      editing = false;
                      fillAddress(state.origin);
                      invalidateSaved();
                      remember = false;
                      username.text = state.accountName.isEmpty
                          ? 'admin'
                          : state.accountName;
                      notice = null;
                    }),
              child: const Text('取消修改'),
            ),
        ],
      ),
    );
  }

  Widget mfaForm(AppState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('验证身份', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('输入验证器中的动态码，或使用恢复码。记住的密码会在验证通过后保存。'),
      const SizedBox(height: 24),
      TextField(
        key: const ValueKey('nas-mfa-field'),
        controller: code,
        enabled: !working,
        autocorrect: false,
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: TextInputAction.go,
        decoration: const InputDecoration(labelText: '动态码或恢复码'),
        onSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('nas-submit'),
        onPressed: working ? null : submit,
        child: Text(working ? '正在验证…' : '验证并登录'),
      ),
      TextButton(
        onPressed: working
            ? null
            : () async {
                if (working) return;
                setState(() => localBusy = true);
                try {
                  await uiTask(context, () async {
                    await state.api.forget();
                    if (!mounted) return;
                    setState(() {
                      state.mfaRequired = false;
                      state.error = null;
                      state.retryAfter = null;
                      pendingLogin = null;
                      pendingPassword = null;
                      code.clear();
                      useSavedPassword = false;
                    });
                  });
                } finally {
                  if (mounted) setState(() => localBusy = false);
                }
              },
        child: const Text('返回密码登录'),
      ),
    ],
  );

  List<Widget> accountManagement(AppState state) => [
    Card(
      key: const ValueKey('nas-status-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.dns_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '家里的曲库',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        checked ? '连接检查通过' : 'NAS 地址已保存',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            detail(
              '曲库地址',
              SelectableText(
                state.origin,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const Divider(),
            detail(
              '账号状态',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('已登录家庭曲库'),
                  if (state.accountName.isNotEmpty)
                    Text(
                      state.accountName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 24),
    const SectionTitle('连接管理'),
    const SizedBox(height: 12),
    Card(
      child: Column(
        children: [
          management(
            Icons.refresh_rounded,
            state.busy ? '检查连接中…' : '检查连接',
            '确认家庭曲库可以正常访问',
            working
                ? null
                : () async {
                    await state.connect(state.origin);
                    if (mounted) setState(() => checked = state.error == null);
                  },
          ),
          const Divider(indent: 16),
          management(
            Icons.edit_outlined,
            '修改 NAS 地址',
            '收藏和练唱记录按曲库分别保留',
            working
                ? null
                : () => setState(() {
                    editing = true;
                    checked = false;
                    fillAddress(state.origin);
                  }),
          ),
          const Divider(indent: 16),
          management(
            Icons.history_rounded,
            '历史登录',
            '选择已连接过的 NAS 和账号',
            working ? null : showHistory,
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    const SectionTitle('账号'),
    const SizedBox(height: 12),
    Card(
      child: management(
        Icons.logout_rounded,
        '退出登录',
        state.accountName.isEmpty ? '账号已登录' : '当前账号：${state.accountName}',
        working ? null : logout,
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final message = notice ?? state.error;
      return Scaffold(
        appBar: AppBar(
          title: Text(state.authenticated && !editing ? 'NAS 连接与账号' : '连接 NAS'),
        ),
        body: SafeArea(
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (state.mfaRequired)
                  mfaForm(state)
                else if (state.authenticated && !editing)
                  ...accountManagement(state)
                else
                  loginForm(state),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '$message${notice == null && state.retryAfter?.isNotEmpty == true ? '，请在 ${state.retryAfter} 秒后重试' : ''}',
                        key: const ValueKey('connection-message'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  '作品和草稿保存在此手机。退出登录或修改地址后，仍可在原曲库的作品中继续回听。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String connectionError(Object error) => switch (error) {
  FormatException() => error.message,
  PlatformException() => error.message ?? '操作未完成，请重试',
  _ => '操作未完成，请检查网络后重试',
};

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
  final backdrop = BackdropKey();
  final address = TextEditingController();
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  final code = TextEditingController();
  late final vault = widget.loginStore ?? widget.state.loginStore;
  bool editing = false, checked = false, localBusy = false;
  bool remember = false, visible = false, useSavedPassword = false;
  bool automatic = false;
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
      automatic = record.hasPassword && widget.state.automaticLoginFor(record);
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
        if (automatic && (secret == null || secret.isEmpty)) {
          throw const FormatException('自动登录需要保存密码，请重新输入密码');
        }
        await vault.save(record, password: secret);
        await widget.state.setAutomaticLogin(automatic ? record : null);
      } catch (_) {
        if (mounted) setState(() => notice = '已登录，但未能保存登录设置，请稍后重试');
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
        secret ??= password.text.isEmpty ? null : password.text;
        if (automatic && (secret == null || secret.isEmpty)) {
          throw const FormatException('自动登录需要保存密码，请重新输入密码');
        }
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
      setState(() {
        formRevision++;
        remember = value;
        if (!value) automatic = false;
      });
      return;
    }
    setState(() => localBusy = true);
    try {
      if (widget.state.automaticLoginFor(record)) {
        await widget.state.setAutomaticLogin(null);
      }
      await vault.forgetPassword(record);
      if (mounted) {
        setState(() {
          remember = false;
          automatic = false;
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

  Future<void> changeAutomatic(bool value) async {
    if (working) return;
    final record = selected;
    setState(() {
      formRevision++;
      automatic = value;
      if (value) remember = true;
    });
    if (!value && record != null && widget.state.automaticLoginFor(record)) {
      setState(() => localBusy = true);
      try {
        await widget.state.setAutomaticLogin(null);
      } catch (error) {
        if (mounted) setState(() => notice = connectionError(error));
      } finally {
        if (mounted) setState(() => localBusy = false);
      }
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
          if (widget.state.automaticLoginFor(selected!)) {
            await widget.state.setAutomaticLogin(null);
            if (!mounted) return;
          }
          setState(() {
            selected = current;
            useSavedPassword = false;
            remember = false;
            automatic = false;
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
        automatic = false;
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
    final yes = await showAppDialog<bool>(
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
    padding: const EdgeInsets.symmetric(vertical: 14),
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
            SizedBox(width: 68, child: caption),
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
    minTileHeight: widget.state.senior ? 88 : 60,
    leading: Icon(icon, size: 20),
    title: Text(
      title,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w400),
    ),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
    onTap: action,
  );

  Widget managementHeading(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: widget.state.senior ? 17 : 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );

  Widget loginForm(AppState state) {
    final theme = Theme.of(context);
    final inputStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: state.senior ? 18 : 16,
      height: 1.25,
    );
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: state.senior ? 17 : 13,
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    InputDecoration decoration({
      String? hint,
      String? prefix,
      Widget? suffix,
    }) => InputDecoration(
      hintText: hint,
      hintStyle: inputStyle?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      prefixText: prefix,
      prefixStyle: inputStyle,
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.surface,
      constraints: BoxConstraints(minHeight: state.senior ? 64 : 52),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.2),
      ),
    );
    Widget labelledField(String label, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: Text(label, style: labelStyle)),
        const SizedBox(height: 8),
        Semantics(label: label, child: field),
      ],
    );
    Widget option(
      String label,
      String key,
      bool value,
      ValueChanged<bool> action,
    ) => MergeSemantics(
      child: InkWell(
        onTap: working ? null : () => action(!value),
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: state.senior ? 56 : 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                key: ValueKey(key),
                value: value,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                onChanged: working ? null : (value) => action(value ?? false),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  label,
                  style: labelStyle?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        key: const ValueKey('nas-account-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!state.senior) ...[
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppPalette.brand, AppPalette.coral],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.brand.withValues(alpha: .32),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.dns_rounded,
                  size: 28,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Semantics(
            header: true,
            child: Text(
              '连接你的家庭曲库',
              textAlign: state.senior ? TextAlign.start : TextAlign.center,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontSize: state.senior ? 32 : 26,
                height: 1.25,
                letterSpacing: -.6,
              ),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, size) => Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                ExcludeSemantics(child: Text('NAS 地址', style: labelStyle)),
                SizedBox(
                  width: (160 * MediaQuery.textScalerOf(context).scale(14) / 14)
                      .clamp(160, size.maxWidth),
                  child: Semantics(
                    label: '连接协议',
                    child: AppSegments<String>(
                      key: const ValueKey('nas-protocol'),
                      liquid: true,
                      values: const [('http', 'HTTP'), ('https', 'HTTPS')],
                      selected: scheme,
                      senior: state.senior,
                      enabled: !working,
                      textStyle: labelStyle,
                      onChanged: (value) {
                        if (value == scheme) return;
                        setState(() {
                          invalidateSaved();
                          scheme = value;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'NAS 地址',
            child: TextField(
              key: const ValueKey('nas-address-field'),
              style: inputStyle,
              controller: address,
              enabled: !working,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: decoration(
                hint: '192.168.1.10:18080',
                prefix: '$scheme://',
                suffix: IconButton(
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
          ),
          const SizedBox(height: 24),
          labelledField(
            '管理员账号',
            TextField(
              key: const ValueKey('nas-username-field'),
              style: inputStyle,
              controller: username,
              enabled: !working,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: decoration(hint: '管理员账号'),
              onChanged: (_) => setState(invalidateSaved),
            ),
          ),
          const SizedBox(height: 20),
          labelledField(
            useSavedPassword ? '已保存密码' : '密码',
            TextField(
              key: const ValueKey('nas-password-field'),
              style: inputStyle,
              controller: password,
              enabled: !working,
              obscureText: !visible,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: remember ? const [AutofillHints.password] : null,
              textInputAction: TextInputAction.go,
              decoration: decoration(
                hint: useSavedPassword ? '登录时自动填入' : '输入 NAS 账号密码',
                suffix: IconButton(
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
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              option('记住密码', 'remember-password', remember, changeRemember),
              option('自动登录', 'automatic-login', automatic, changeAutomatic),
              TextButton(
                key: const ValueKey('forgot-password'),
                style: TextButton.styleFrom(
                  textStyle: labelStyle?.copyWith(fontWeight: FontWeight.w400),
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: working ? null : forgotPassword,
                child: const Text('忘记密码？'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('nas-submit'),
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(state.senior ? 60 : 52),
              shape: const StadiumBorder(),
              textStyle: theme.textTheme.titleMedium,
            ),
            onPressed: working ? null : submit,
            child: Text(working ? '正在连接…' : '登录并连接'),
          ),
          const SizedBox(height: 16),
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
                      automatic = false;
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
    Glass(
      key: const ValueKey('nas-status-card'),
      state: state,
      radius: 24,
      material: GlassMaterialSpec.standard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [AppPalette.brand, AppPalette.coral],
                    ),
                  ),
                  child: const Icon(
                    Icons.dns_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '家里的曲库',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
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
    managementHeading('连接管理'),
    const SizedBox(height: 8),
    Glass(
      state: state,
      radius: 24,
      material: GlassMaterialSpec.standard,
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
          const Divider(indent: 16, endIndent: 16),
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
                    loadRecent();
                  }),
          ),
          const Divider(indent: 16, endIndent: 16),
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
    managementHeading('账号'),
    const SizedBox(height: 8),
    Glass(
      state: state,
      radius: 24,
      material: GlassMaterialSpec.standard,
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
      final solid =
          AppMotionScope.solidOf(context) ||
          state.senior ||
          state.reduceTransparency ||
          state.performanceMode;
      return AppEnvironment(
        solid: solid,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: state.senior ? 64 : 52,
            centerTitle: true,
            systemOverlayStyle:
                (Theme.of(context).brightness == Brightness.dark
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark)
                    .copyWith(statusBarColor: Colors.transparent),
            leadingWidth: state.senior ? 76 : 60,
            leading: Navigator.canPop(context)
                ? Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    child: Glass(
                      state: state,
                      radius: 26,
                      variant: GlassVariant.liquid,
                      child: BackButton(
                        style: IconButton.styleFrom(
                          minimumSize: Size.square(state.senior ? 56 : 44),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  )
                : null,
            title: Text(
              state.authenticated && !editing ? 'NAS 连接与账号' : '连接 NAS',
            ),
          ),
          body: BackdropGroup(
            backdropKey: backdrop,
            child: SafeArea(
              child: ContentWidth(
                child: ListView(
                  key: const ValueKey('nas-page-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    MediaQuery.sizeOf(context).width < 375 ? 16 : 20,
                    24,
                    MediaQuery.sizeOf(context).width < 375 ? 16 : 20,
                    32,
                  ),
                  children: [
                    if (state.mfaRequired)
                      mfaForm(state)
                    else if (state.authenticated && !editing)
                      ...accountManagement(state)
                    else
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: loginForm(state),
                        ),
                      ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            '$message${notice == null && state.retryAfter?.isNotEmpty == true ? '，请在 ${state.retryAfter} 秒后重试' : ''}',
                            key: const ValueKey('connection-message'),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
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
    },
  );
}

String connectionError(Object error) => switch (error) {
  FormatException() => error.message,
  PlatformException() => error.message ?? '操作未完成，请重试',
  _ => '操作未完成，请检查网络后重试',
};

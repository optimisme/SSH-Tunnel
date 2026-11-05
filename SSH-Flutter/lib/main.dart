import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n.dart';
import 'ssh_config_file.dart';
import 'ssh_config_store.dart';
import 'ssh_connection_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  updateL10n();

  await windowManager.ensureInitialized();
  // The close button asks about open tunnels first (see onWindowClose).
  await windowManager.setPreventClose(true);
  windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(850, 775),
      minimumSize: const Size(800, 600),
      title: l10n.appTitle,
      center: true,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final store = SSHConfigStore();
  await store.initialize();
  runApp(SSHFlutterApp(store: store));
}

class SSHFlutterApp extends StatelessWidget {
  const SSHFlutterApp({super.key, required this.store});

  final SSHConfigStore store;

  @override
  Widget build(BuildContext context) {
    return CDKApp(
      defaultAppearance: CDKThemeAppearance.system,
      defaultColor: 'systemBlue',
      child: LocalizedRoot(child: SSHHomePage(store: store)),
    );
  }
}

/// CDKApp has no localization hooks: inject the app's delegates here and
/// follow changes to the system languages.
class LocalizedRoot extends StatefulWidget {
  const LocalizedRoot({super.key, required this.child});

  final Widget child;

  @override
  State<LocalizedRoot> createState() => _LocalizedRootState();
}

class _LocalizedRootState extends State<LocalizedRoot>
    with WidgetsBindingObserver {
  late Locale _locale = resolveAppLocale(PlatformDispatcher.instance.locales);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    setState(() => _locale = updateL10n(locales));
  }

  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      locale: _locale,
      delegates: const [
        AppLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      child: widget.child,
    );
  }
}

class AppTextStyles {
  static const TextStyle sidebarTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle bodySmall = TextStyle(fontSize: 12);
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle status = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle terminal = TextStyle(
    fontFamily: 'SF Mono',
    fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
    fontSize: 12,
    height: 1.3,
  );
}

class SSHHomePage extends StatefulWidget {
  const SSHHomePage({super.key, required this.store});

  final SSHConfigStore store;

  @override
  State<SSHHomePage> createState() => _SSHHomePageState();
}

class _SSHHomePageState extends State<SSHHomePage> with WindowListener {
  double _sidebarWidth = 240;
  double? _sidebarDragStartWidth;
  double? _sidebarDragStartX;
  final GlobalKey _settingsAnchor = GlobalKey();

  late final AppLifecycleListener _lifecycle;
  bool _exitApproved = false;
  Future<bool>? _pendingQuit;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _lifecycle.dispose();
    super.dispose();
  }

  // MARK: Quitting

  /// Cmd+Q / app menu Quit.
  Future<AppExitResponse> _onExitRequested() async {
    if (_exitApproved) return AppExitResponse.exit;
    return await _prepareToQuit()
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  /// Window close button (the app quits with its only window).
  @override
  void onWindowClose() {
    unawaited(() async {
      if (!await _prepareToQuit()) return;
      _exitApproved = true;
      await windowManager.destroy();
    }());
  }

  /// Returns false when the user cancels. Never asks twice at the same time.
  Future<bool> _prepareToQuit() {
    return _pendingQuit ??= _runQuitFlow().whenComplete(() {
      _pendingQuit = null;
    });
  }

  Future<bool> _runQuitFlow() async {
    final store = widget.store;
    final running = store.runningConfigurations.length;
    if (running > 0) {
      var behavior = store.quitBehavior;
      if (behavior == QuitBehavior.ask) {
        await windowManager.show();
        await windowManager.focus();
        if (!mounted) return true;
        final choice = await showQuitDialog(context, running);
        if (choice == null) return false;
        if (choice.dontAskAgain) store.quitBehavior = choice.behavior;
        behavior = choice.behavior;
      }
      if (behavior == QuitBehavior.closeTunnels) await store.stopAll();
    }
    await store.saveNow();
    _exitApproved = true;
    return true;
  }

  // MARK: Actions

  Future<void> _confirmRemove(
    BuildContext context,
    SSHConfiguration selected,
  ) async {
    final t = tr(context);
    final ok = await CDKDialogsManager.showConfirm(
      context: context,
      title: t.deleteConfirmTitle(selected.name),
      message: t.deleteConfirmMessage,
      confirmLabel: t.delete,
      cancelLabel: t.cancel,
      isDestructive: true,
    );
    if (ok == true) widget.store.remove(selected.id);
  }

  void _showSettings(BuildContext context) {
    final controller = CDKDialogController();
    CDKDialogsManager.showPopover(
      context: context,
      anchorKey: _settingsAnchor,
      type: CDKDialogPopoverType.down,
      controller: controller,
      child: SettingsPanel(store: widget.store),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final selected = widget.store.selectedConfiguration;
        final scaffoldColor = CupertinoColors.systemGroupedBackground
            .resolveFrom(context);
        final sidebarColor = CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context);
        final dividerColor = CupertinoColors.separator.resolveFrom(context);
        final secondaryLabelColor = CupertinoColors.secondaryLabel.resolveFrom(
          context,
        );
        return CupertinoPageScaffold(
          backgroundColor: scaffoldColor,
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: _sidebarWidth,
                  padding: const EdgeInsets.all(12),
                  color: sidebarColor,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.sidebarTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.sidebarTitle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ReorderableList(
                          itemCount: widget.store.configurations.length,
                          onReorder: widget.store.move,
                          itemBuilder: (context, index) {
                            final cfg = widget.store.configurations[index];
                            final isSelected =
                                cfg.id == widget.store.selectedId;
                            final sidebarTextColor =
                                CDKThemeNotifier.of(context)!.changeNotifier
                                    .getSidebarColorText(isSelected, true);
                            return Padding(
                              key: ValueKey<String>(cfg.id),
                              padding: const EdgeInsets.only(bottom: 6),
                              child: CDKButtonSidebar(
                                isSelected: isSelected,
                                onSelected: () =>
                                    widget.store.selectConfiguration(cfg.id),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: CupertinoDynamicColor.resolve(
                                          cfg.connection.statusColor,
                                          context,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        cfg.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: sidebarTextColor,
                                        ),
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: DragHandle(
                                        color: sidebarTextColor.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CDKButton(
                            onPressed: widget.store.addConfiguration,
                            child: Text('+ ${t.add}'),
                          ),
                          const Spacer(),
                          CDKButtonIcon(
                            key: _settingsAnchor,
                            onPressed: () => _showSettings(context),
                            icon: CupertinoIcons.gear,
                            semanticLabel: t.settings,
                            size: 22,
                          ),
                          const SizedBox(width: 4),
                          CDKButtonIcon(
                            onPressed: selected == null
                                ? null
                                : () => _confirmRemove(context, selected),
                            icon: CupertinoIcons.delete,
                            semanticLabel: t.deleteConfiguration,
                            size: 22,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // No native split view in Flutter: a 1 px divider that can be dragged.
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      _sidebarDragStartWidth = _sidebarWidth;
                      _sidebarDragStartX = details.globalPosition.dx;
                    },
                    onHorizontalDragUpdate: (details) {
                      final startWidth =
                          _sidebarDragStartWidth ?? _sidebarWidth;
                      final startX =
                          _sidebarDragStartX ?? details.globalPosition.dx;
                      final proposed =
                          startWidth + (details.globalPosition.dx - startX);
                      setState(() {
                        _sidebarWidth = proposed.clamp(170, 340).toDouble();
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      _sidebarDragStartWidth = null;
                      _sidebarDragStartX = null;
                    },
                    child: Container(width: 1, color: dividerColor),
                  ),
                ),
                Expanded(
                  child: selected == null
                      ? Center(
                          child: Text(
                            t.noSelection,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: secondaryLabelColor,
                            ),
                          ),
                        )
                      : ConnectionDetailView(
                          key: ValueKey<String>(selected.id),
                          configuration: selected,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class DragHandle extends StatelessWidget {
  const DragHandle({super.key, required this.color, this.enabled = true});

  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr(context).dragToReorder,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            CupertinoIcons.line_horizontal_3,
            size: 14,
            color: enabled ? color : color.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

// MARK: - Quit dialog and settings

class QuitChoice {
  const QuitChoice(this.behavior, this.dontAskAgain);
  final QuitBehavior behavior;
  final bool dontAskAgain;
}

/// Asks what to do with [count] open tunnels. Null means "don't quit".
Future<QuitChoice?> showQuitDialog(BuildContext context, int count) {
  if (Overlay.maybeOf(context) == null) return Future.value(null);
  final controller = CDKDialogController();
  final completer = Completer<QuitChoice?>();
  QuitChoice? result;
  CDKDialogsManager.showModal(
    context: context,
    controller: controller,
    showBackgroundShade: true,
    onHide: () {
      if (!completer.isCompleted) completer.complete(result);
    },
    child: QuitDialog(
      count: count,
      onChoice: (choice) {
        result = choice;
        controller.close();
      },
    ),
  );
  return completer.future;
}

class QuitDialog extends StatefulWidget {
  const QuitDialog({super.key, required this.count, required this.onChoice});

  final int count;
  final ValueChanged<QuitChoice?> onChoice;

  @override
  State<QuitDialog> createState() => _QuitDialogState();
}

class _QuitDialogState extends State<QuitDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    void choose(QuitBehavior behavior) =>
        widget.onChoice(QuitChoice(behavior, _dontAskAgain));
    return SizedBox(
      width: 420,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.quitTitle(widget.count), style: AppTextStyles.sectionTitle),
            const SizedBox(height: 8),
            Text(t.quitMessage, style: AppTextStyles.bodySmall),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => setState(() => _dontAskAgain = !_dontAskAgain),
              child: Row(
                children: [
                  CDKButtonCheckBox(
                    value: _dontAskAgain,
                    onChanged: (v) => setState(() => _dontAskAgain = v),
                  ),
                  const SizedBox(width: 6),
                  Text(t.dontAskAgain, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Wraps when long translations do not fit on one line.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                CDKButton(
                  onPressed: () => widget.onChoice(null),
                  child: Text(t.cancel),
                ),
                CDKButton(
                  onPressed: () => choose(QuitBehavior.keepTunnels),
                  child: Text(t.keepRunning),
                ),
                CDKButton(
                  style: CDKButtonStyle.action,
                  onPressed: () => choose(QuitBehavior.closeTunnels),
                  child: Text(t.closeTunnels),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.store});

  final SSHConfigStore store;

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final options = {
      QuitBehavior.ask: t.quitAsk,
      QuitBehavior.closeTunnels: t.quitClose,
      QuitBehavior.keepTunnels: t.quitKeep,
    };
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.quitBehaviorLabel, style: AppTextStyles.bodySmall),
            const SizedBox(height: 8),
            for (final entry in options.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: CDKButtonRadio(
                  isSelected: store.quitBehavior == entry.key,
                  onSelected: (_) => store.quitBehavior = entry.key,
                  child: Text(entry.value, style: AppTextStyles.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ConnectionDetailView extends StatefulWidget {
  const ConnectionDetailView({super.key, required this.configuration});

  final SSHConfiguration configuration;

  @override
  State<ConnectionDetailView> createState() => _ConnectionDetailViewState();
}

class _ConnectionDetailViewState extends State<ConnectionDetailView> {
  SSHConnectionController get _connection => widget.configuration.connection;

  final GlobalKey _hostMenuAnchor = GlobalKey();
  final GlobalKey _keyMenuAnchor = GlobalKey();

  List<String> _aliases = const [];
  ResolvedSshHost? _resolved;
  String _resolvedFor = '';
  Timer? _resolveTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_connection.refresh());
    _aliases = SshConfigFile.hostAliases();
    _connection.addListener(_hostMaybeChanged);
    _hostMaybeChanged();
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _connection.removeListener(_hostMaybeChanged);
    super.dispose();
  }

  /// Looks the host up with `ssh -G` when it is a ~/.ssh/config alias.
  void _hostMaybeChanged() {
    final host = _connection.host.trim();
    if (host == _resolvedFor) return;
    _resolvedFor = host;
    _resolveTimer?.cancel();
    if (!_aliases.contains(host)) {
      if (_resolved != null) setState(() => _resolved = null);
      return;
    }
    _resolveTimer = Timer(const Duration(milliseconds: 300), () async {
      final resolved = await SshConfigFile.resolve(
        SSHConnectionController.sshPath,
        host,
      );
      if (!mounted || _resolvedFor != host) return;
      setState(() => _resolved = resolved);
    });
  }

  String get _localUserName =>
      Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? '';

  void _showHostMenu(BuildContext context) {
    final t = tr(context);
    _aliases = SshConfigFile.hostAliases();
    final controller = CDKDialogController();
    CDKDialogsManager.showPopover(
      context: context,
      anchorKey: _hostMenuAnchor,
      type: CDKDialogPopoverType.down,
      controller: controller,
      child: PickerMenu(
        title: t.hostsFromSshConfig,
        emptyText: t.noHostsInSshConfig,
        entries: [
          for (final alias in _aliases)
            PickerEntry(alias, () {
              controller.close();
              _connection.setHost(alias);
            }, selected: alias == _connection.host.trim()),
        ],
      ),
    );
  }

  void _showKeyMenu(BuildContext context) {
    final t = tr(context);
    final keys = SshConfigFile.privateKeys();
    final current = _connection.keyPath.trim();
    final controller = CDKDialogController();
    CDKDialogsManager.showPopover(
      context: context,
      anchorKey: _keyMenuAnchor,
      type: CDKDialogPopoverType.down,
      controller: controller,
      child: PickerMenu(
        entries: [
          PickerEntry(t.useAgent, () {
            controller.close();
            _connection.setKeyPath('');
          }, selected: current.isEmpty),
          null,
          for (final key in keys)
            PickerEntry(key, () {
              controller.close();
              _connection.setKeyPath(key);
            }, selected: key == current),
          if (keys.isNotEmpty) null,
          PickerEntry(t.chooseFile, () {
            controller.close();
            unawaited(_chooseKeyFile(t));
          }),
        ],
      ),
    );
  }

  Future<void> _chooseKeyFile(AppLocalizations t) async {
    final current = SshConfigFile.expandHome(_connection.keyPath.trim());
    final dir = current.isNotEmpty && File(current).existsSync()
        ? File(current).parent.path
        : SshConfigFile.sshDirectory;
    final file = await openFile(
      initialDirectory: dir,
      confirmButtonText: t.choose,
    );
    if (file == null) return;
    _connection.setKeyPath(SshConfigFile.abbreviatingHome(file.path));
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final logPanelBorderColor = CupertinoColors.separator.resolveFrom(context);
    final logPanelBackgroundColor = CupertinoColors
        .tertiarySystemGroupedBackground
        .resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);
    return AnimatedBuilder(
      animation: _connection,
      builder: (context, _) {
        final isRunning = _connection.isRunning;
        final forwardRules = _connection.forwardRules;
        final statusColor = CupertinoDynamicColor.resolve(
          _connection.statusColor,
          context,
        );
        final resolved = _resolved;
        final userPrompt = resolved != null && resolved.user.isNotEmpty
            ? t.userPlaceholderFromConfig(resolved.user)
            : t.userPlaceholderDefault(_localUserName);
        final portPrompt = resolved != null && resolved.port.isNotEmpty
            ? resolved.port
            : '22';
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BoundTextField(
                value: widget.configuration.name,
                enabled: true,
                label: t.configurationName,
                labelStyle: AppTextStyles.sectionTitle,
                onChanged: widget.configuration.setName,
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: t.sshConnection,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rowField(
                      t.host,
                      _connection.host,
                      _connection.setHost,
                      enabled: !isRunning,
                      placeholder: t.hostPlaceholder,
                      trailing: CDKButtonIcon(
                        key: _hostMenuAnchor,
                        onPressed: isRunning
                            ? null
                            : () => _showHostMenu(context),
                        icon: CupertinoIcons.list_bullet,
                        semanticLabel: t.hostsFromSshConfig,
                        size: 22,
                      ),
                    ),
                    if (resolved != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 72, top: 4),
                        child: Text(
                          t.fromSshConfig(resolved.summary),
                          style: AppTextStyles.label.copyWith(
                            color: secondaryLabel,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _rowField(
                      t.user,
                      _connection.user,
                      _connection.setUser,
                      enabled: !isRunning,
                      placeholder: userPrompt,
                    ),
                    const SizedBox(height: 8),
                    _rowField(
                      t.port,
                      _connection.sshPort,
                      _connection.setSshPort,
                      enabled: !isRunning,
                      width: 100,
                      keyboardType: TextInputType.number,
                      placeholder: portPrompt,
                    ),
                    const SizedBox(height: 8),
                    _rowField(
                      t.key,
                      _connection.keyPath,
                      _connection.setKeyPath,
                      enabled: !isRunning,
                      placeholder: t.keyPlaceholder,
                      trailing: CDKButtonIcon(
                        key: _keyMenuAnchor,
                        onPressed: isRunning
                            ? null
                            : () => _showKeyMenu(context),
                        icon: CupertinoIcons.folder,
                        semanticLabel: t.chooseKey,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: t.forwardRules,
                child: Column(
                  children: [
                    ReorderableList(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: forwardRules.length,
                      onReorder: (from, to) {
                        if (to > from) to -= 1;
                        _connection.moveForwardRule(from, to);
                      },
                      proxyDecorator: (child, index, animation) => Container(
                        decoration: BoxDecoration(
                          color: CupertinoColors
                              .secondarySystemGroupedBackground
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(blurRadius: 6, color: Color(0x33000000)),
                          ],
                        ),
                        child: child,
                      ),
                      itemBuilder: (context, index) => _ruleRow(
                        context,
                        t,
                        forwardRules[index],
                        index,
                        isRunning: isRunning,
                        canDelete: forwardRules.length > 1,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CDKButton(
                        onPressed: isRunning
                            ? null
                            : _connection.addForwardRule,
                        child: Text('+ ${t.addRule}'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.autoReconnect,
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  CDKButtonSwitch(
                    value: _connection.autoReconnect,
                    onChanged: _connection.setAutoReconnect,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SectionCard(
                title: t.sshOutput,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 125,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: logPanelBorderColor),
                        color: logPanelBackgroundColor,
                      ),
                      child: SingleChildScrollView(
                        reverse: true, // keep the latest output visible
                        child: SelectableText(
                          _connection.logText.isEmpty
                              ? '—'
                              : _connection.logText,
                          style: AppTextStyles.terminal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CDKButton(
                        onPressed: _connection.clearLog,
                        child: Text(t.clear),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CDKButton(
                    onPressed: _connection.isRunning ? null : _connection.start,
                    style: CDKButtonStyle.action,
                    child: Text(t.connect),
                  ),
                  const SizedBox(width: 8),
                  CDKButton(
                    onPressed: _connection.isRunning && !_connection.isStopping
                        ? () {
                            unawaited(_connection.stop());
                          }
                        : null,
                    child: Text(t.disconnect),
                  ),
                  const SizedBox(width: 8),
                  CDKButton(
                    onPressed: () {
                      unawaited(_connection.refresh());
                    },
                    child: Text(t.refresh),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _connection.statusLabel,
                        style: AppTextStyles.status.copyWith(
                          color: statusColor,
                        ),
                      ),
                      if (_connection.statusDetail.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            _connection.statusDetail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: secondaryLabel,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ruleRow(
    BuildContext context,
    AppLocalizations t,
    PortForwardRule rule,
    int index, {
    required bool isRunning,
    required bool canDelete,
  }) {
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final handle = DragHandle(color: labelColor, enabled: !isRunning);
    return Padding(
      key: ValueKey<String>(rule.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (isRunning)
            handle
          else
            ReorderableDragStartListener(index: index, child: handle),
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            child: Text(t.ruleName, style: AppTextStyles.bodySmall),
          ),
          SizedBox(
            width: 130,
            child: BoundTextField(
              value: rule.name,
              enabled: !isRunning,
              onChanged: (v) => _connection.updateRuleName(rule.id, v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(t.ruleLocal, style: AppTextStyles.bodySmall),
          ),
          SizedBox(
            width: 70,
            child: BoundTextField(
              value: rule.localPort,
              enabled: !isRunning,
              keyboardType: TextInputType.number,
              onChanged: (v) => _connection.updateRuleLocalPort(rule.id, v),
            ),
          ),
          const SizedBox(width: 6),
          const Text('→', style: AppTextStyles.bodySmall),
          const SizedBox(width: 6),
          Expanded(
            child: BoundTextField(
              value: rule.remoteHost,
              enabled: !isRunning,
              onChanged: (v) => _connection.updateRuleRemoteHost(rule.id, v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: BoundTextField(
              value: rule.remotePort,
              enabled: !isRunning,
              keyboardType: TextInputType.number,
              onChanged: (v) => _connection.updateRuleRemotePort(rule.id, v),
            ),
          ),
          const SizedBox(width: 8),
          CDKButtonIcon(
            onPressed: (isRunning || !canDelete)
                ? null
                : () => _connection.removeForwardRule(rule.id),
            icon: CupertinoIcons.delete,
            semanticLabel: t.deleteRule,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _rowField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    required bool enabled,
    double? width,
    TextInputType? keyboardType,
    String? placeholder,
    Widget? trailing,
  }) {
    final field = BoundTextField(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: keyboardType,
      placeholder: placeholder,
    );

    return Row(
      children: [
        SizedBox(width: 72, child: Text(label, style: AppTextStyles.bodySmall)),
        if (width == null)
          Expanded(child: field)
        else
          SizedBox(width: width, child: field),
        if (trailing != null) ...[const SizedBox(width: 6), trailing],
      ],
    );
  }
}

class PickerEntry {
  const PickerEntry(this.label, this.onTap, {this.selected = false});
  final String label;
  final VoidCallback onTap;
  final bool selected;
}

/// A simple menu for popovers; `null` entries are separators.
class PickerMenu extends StatelessWidget {
  const PickerMenu({
    super.key,
    required this.entries,
    this.title,
    this.emptyText,
  });

  final List<PickerEntry?> entries;
  final String? title;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final hasItems = entries.any((e) => e != null);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 220,
        maxWidth: 360,
        maxHeight: 360,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                child: Text(
                  title!,
                  style: AppTextStyles.label.copyWith(color: secondary),
                ),
              ),
            if (!hasItems && emptyText != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  emptyText!,
                  style: AppTextStyles.bodySmall.copyWith(color: secondary),
                ),
              ),
            for (final entry in entries)
              if (entry == null)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: separator,
                )
              else
                _PickerRow(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatefulWidget {
  const _PickerRow({required this.entry});
  final PickerEntry entry;

  @override
  State<_PickerRow> createState() => _PickerRowState();
}

class _PickerRowState extends State<_PickerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = CDKThemeNotifier.of(context)!.changeNotifier;
    final textColor = _hover
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.entry.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: _hover ? theme.accent : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: widget.entry.selected
                    ? Icon(CupertinoIcons.checkmark, size: 12, color: textColor)
                    : null,
              ),
              Flexible(
                child: Text(
                  widget.entry.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cardColor = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final cardBorderColor = CupertinoColors.separator.resolveFrom(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.sectionTitle),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class BoundTextField extends StatefulWidget {
  const BoundTextField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.label,
    this.labelStyle,
    this.keyboardType,
    this.placeholder,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String? label;
  final TextStyle? labelStyle;
  final TextInputType? keyboardType;
  final String? placeholder;

  @override
  State<BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<BoundTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant BoundTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = CDKFieldText(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      placeholder: widget.label ?? widget.placeholder ?? '',
      textSize: 12,
      onChanged: widget.onChanged,
    );

    if (widget.label == null) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label!, style: widget.labelStyle ?? AppTextStyles.label),
        const SizedBox(height: 4),
        field,
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'ssh_config_store.dart';
import 'ssh_connection_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(850, 775),
      minimumSize: Size(800, 600),
      title: 'SSH Túnel',
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
      child: SSHHomePage(store: store),
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

class _SSHHomePageState extends State<SSHHomePage> {
  double _sidebarWidth = 240;
  double? _sidebarDragStartWidth;
  double? _sidebarDragStartX;

  Future<void> _confirmRemove(
    BuildContext context,
    SSHConfiguration selected,
  ) async {
    final ok = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Eliminar «${selected.name}»?',
      message: "Si el túnel està actiu, s'aturarà.",
      confirmLabel: 'Eliminar',
      cancelLabel: 'Cancel·lar',
      isDestructive: true,
    );
    if (ok == true && widget.store.selectedId == selected.id) {
      widget.store.removeSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                              'Configuracions SSH',
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
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.grab,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: Icon(
                                            CupertinoIcons.line_horizontal_3,
                                            size: 14,
                                            color: sidebarTextColor.withValues(
                                              alpha: 0.6,
                                            ),
                                          ),
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
                            child: const Text('+ Afegir'),
                          ),
                          const Spacer(),
                          CDKButtonIcon(
                            onPressed: selected == null
                                ? null
                                : () => _confirmRemove(context, selected),
                            icon: CupertinoIcons.delete,
                            semanticLabel: 'Eliminar',
                            size: 22,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
                        _sidebarWidth = proposed.clamp(160, 360).toDouble();
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
                            'Selecciona o crea una configuració',
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

class ConnectionDetailView extends StatefulWidget {
  const ConnectionDetailView({super.key, required this.configuration});

  final SSHConfiguration configuration;

  @override
  State<ConnectionDetailView> createState() => _ConnectionDetailViewState();
}

class _ConnectionDetailViewState extends State<ConnectionDetailView> {
  SSHConnectionController get _connection => widget.configuration.connection;

  @override
  void initState() {
    super.initState();
    unawaited(_connection.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final logPanelBorderColor = CupertinoColors.separator.resolveFrom(context);
    final logPanelBackgroundColor = CupertinoColors
        .tertiarySystemGroupedBackground
        .resolveFrom(context);
    return AnimatedBuilder(
      animation: _connection,
      builder: (context, _) {
        final isRunning = _connection.isRunning;
        final forwardRules = _connection.forwardRules;
        final statusColor = CupertinoDynamicColor.resolve(
          _connection.statusColor,
          context,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BoundTextField(
                value: widget.configuration.name,
                enabled: true,
                label: 'Nom de la configuració',
                labelStyle: AppTextStyles.sectionTitle,
                onChanged: widget.configuration.setName,
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Connexió SSH',
                child: Column(
                  children: [
                    _rowField(
                      'Host',
                      _connection.host,
                      _connection.setHost,
                      enabled: !isRunning,
                    ),
                    const SizedBox(height: 8),
                    _rowField(
                      'Usuari',
                      _connection.user,
                      _connection.setUser,
                      enabled: !isRunning,
                    ),
                    const SizedBox(height: 8),
                    _rowField(
                      'Port',
                      _connection.sshPort,
                      _connection.setSshPort,
                      enabled: !isRunning,
                      width: 100,
                      keyboardType: TextInputType.number,
                      placeholder: '22',
                    ),
                    const SizedBox(height: 8),
                    _rowField(
                      'Clau',
                      _connection.keyPath,
                      _connection.setKeyPath,
                      enabled: !isRunning,
                      placeholder: '~/.ssh/id_ed25519',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Regles de reenviament de port',
                child: Column(
                  children: [
                    for (final rule in forwardRules)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                'Nom',
                                style: AppTextStyles.bodySmall,
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              child: BoundTextField(
                                value: rule.name,
                                enabled: !isRunning,
                                onChanged: (v) =>
                                    _connection.updateRuleName(rule.id, v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              child: Text(
                                'Local',
                                style: AppTextStyles.bodySmall,
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: BoundTextField(
                                value: rule.localPort,
                                enabled: !isRunning,
                                keyboardType: TextInputType.number,
                                onChanged: (v) =>
                                    _connection.updateRuleLocalPort(rule.id, v),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('→', style: AppTextStyles.bodySmall),
                            const SizedBox(width: 6),
                            Expanded(
                              child: BoundTextField(
                                value: rule.remoteHost,
                                enabled: !isRunning,
                                onChanged: (v) => _connection
                                    .updateRuleRemoteHost(rule.id, v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: BoundTextField(
                                value: rule.remotePort,
                                enabled: !isRunning,
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _connection
                                    .updateRuleRemotePort(rule.id, v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CDKButtonIcon(
                              onPressed: (isRunning || forwardRules.length == 1)
                                  ? null
                                  : () =>
                                        _connection.removeForwardRule(rule.id),
                              icon: CupertinoIcons.delete,
                              semanticLabel: 'Eliminar regla',
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CDKButton(
                        onPressed: isRunning
                            ? null
                            : _connection.addForwardRule,
                        child: const Text('+ Afegir regla'),
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
                      "Reconnectar automàticament si es perd la connexió (i en despertar l'ordinador)",
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
                title: 'Sortida (ssh)',
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
                        child: const Text('Netejar'),
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
                    child: const Text('Activar'),
                  ),
                  const SizedBox(width: 8),
                  CDKButton(
                    onPressed: _connection.isRunning && !_connection.isStopping
                        ? () {
                            unawaited(_connection.stop());
                          }
                        : null,
                    child: const Text('Desactivar'),
                  ),
                  const SizedBox(width: 8),
                  CDKButton(
                    onPressed: () {
                      unawaited(_connection.refresh());
                    },
                    child: const Text('Refrescar'),
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
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
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

  Widget _rowField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    required bool enabled,
    double? width,
    TextInputType? keyboardType,
    String? placeholder,
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
      ],
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

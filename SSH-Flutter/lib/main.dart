import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Configuracions SSH',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: widget.store.configurations.length,
                          itemBuilder: (context, index) {
                            final cfg = widget.store.configurations[index];
                            final isSelected =
                                cfg.id == widget.store.selectedId;
                            return Padding(
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
                                        style: const TextStyle(fontSize: 12),
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
                                : widget.store.removeSelected,
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
                            style: TextStyle(color: secondaryLabelColor),
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
    unawaited(_connection.checkInitialState());
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
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
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
                    ),
                    const SizedBox(height: 8),
                    _rowField(
                      'Clau',
                      _connection.keyPath,
                      _connection.setKeyPath,
                      enabled: !isRunning,
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
                            const SizedBox(
                              width: 44,
                              child: Text(
                                'Nom',
                                style: TextStyle(fontSize: 12),
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
                            const SizedBox(
                              width: 48,
                              child: Text(
                                'Local',
                                style: TextStyle(fontSize: 12),
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
                            const Text('→', style: TextStyle(fontSize: 12)),
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
                  const Expanded(
                    child: Text(
                      'Reconnectar automàticament si es perd la connexió',
                      style: TextStyle(fontSize: 12),
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
                        child: SelectableText(
                          _connection.logText.isEmpty
                              ? '—'
                              : _connection.logText,
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 12,
                            height: 1.3,
                          ),
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
                    onPressed: _connection.isRunning
                        ? null
                        : () {
                            unawaited(_connection.start());
                          },
                    style: CDKButtonStyle.action,
                    child: const Text('Activar'),
                  ),
                  const SizedBox(width: 8),
                  CDKButton(
                    onPressed: _connection.isRunning
                        ? () {
                            unawaited(_connection.stop());
                          }
                        : null,
                    child: const Text('Desactivar'),
                  ),
                  const SizedBox(width: 8),
                  CDKButton(
                    onPressed: () {
                      unawaited(_connection.checkInitialState());
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
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
  }) {
    final field = BoundTextField(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: keyboardType,
    );

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
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
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
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
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String? label;
  final TextStyle? labelStyle;
  final TextInputType? keyboardType;

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
      placeholder: widget.label ?? '',
      textSize: 12,
      onChanged: widget.onChanged,
    );

    if (widget.label == null) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label!,
          style:
              widget.labelStyle ??
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        field,
      ],
    );
  }
}

class SSHConfigStore extends ChangeNotifier {
  final List<SSHConfiguration> _configurations = [];
  final Map<String, VoidCallback> _configListeners = {};
  final Map<String, VoidCallback> _connectionListeners = {};

  String? selectedId;
  File? _saveFile;
  Timer? _saveTimer;

  List<SSHConfiguration> get configurations =>
      List.unmodifiable(_configurations);

  SSHConfiguration? get selectedConfiguration {
    if (selectedId == null) {
      return null;
    }
    for (final cfg in _configurations) {
      if (cfg.id == selectedId) {
        return cfg;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    final appSupportDir = await _appSupportDirectory();
    await appSupportDir.create(recursive: true);
    _saveFile = File('${appSupportDir.path}/configs.json');

    if (await _saveFile!.exists()) {
      try {
        final raw = await _saveFile!.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _configurations.add(SSHConfiguration.fromJson(item));
            } else if (item is Map) {
              _configurations.add(
                SSHConfiguration.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      } catch (_) {
        // Keep an empty store if existing config cannot be decoded.
      }
    }

    selectedId = _configurations.isEmpty ? null : _configurations.first.id;
    _attachObservers();
    notifyListeners();
  }

  void selectConfiguration(String id) {
    if (selectedId == id) {
      return;
    }
    selectedId = id;
    _scheduleSave();
    notifyListeners();
  }

  void addConfiguration() {
    final idx = _configurations.length + 1;
    final cfg = SSHConfiguration(
      name: 'Connexió $idx',
      defaultLocalPort: '590$idx',
    );
    _configurations.add(cfg);
    selectedId = cfg.id;
    _attachObservers();
    _scheduleSave();
    notifyListeners();
  }

  void removeSelected() {
    final selected = selectedConfiguration;
    if (selected == null) {
      return;
    }

    final index = _configurations.indexWhere((c) => c.id == selected.id);
    if (index < 0) {
      return;
    }

    unawaited(selected.connection.stop());
    _configurations.removeAt(index);

    if (_configurations.isEmpty) {
      selectedId = null;
    } else {
      final newIndex = min(index, _configurations.length - 1);
      selectedId = _configurations[newIndex].id;
    }

    _attachObservers();
    _scheduleSave();
    notifyListeners();
  }

  void _attachObservers() {
    for (final entry in _configListeners.entries) {
      final cfg = _configurations.where((c) => c.id == entry.key).toList();
      if (cfg.isNotEmpty) {
        cfg.first.removeListener(entry.value);
      }
    }
    for (final entry in _connectionListeners.entries) {
      final cfg = _configurations.where((c) => c.id == entry.key).toList();
      if (cfg.isNotEmpty) {
        cfg.first.connection.removeListener(entry.value);
      }
    }

    _configListeners.clear();
    _connectionListeners.clear();

    for (final cfg in _configurations) {
      void onConfigChange() {
        _scheduleSave();
        notifyListeners();
      }

      void onConnectionChange() {
        _scheduleSave();
        notifyListeners();
      }

      cfg.addListener(onConfigChange);
      cfg.connection.addListener(onConnectionChange);
      _configListeners[cfg.id] = onConfigChange;
      _connectionListeners[cfg.id] = onConnectionChange;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 120), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final file = _saveFile;
    if (file == null) {
      return;
    }

    final snapshots = _configurations.map((c) => c.toJson()).toList();
    try {
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(snapshots));
    } catch (_) {
      // Silent failure to match original app behavior.
    }
  }

  Future<Directory> _appSupportDirectory() async {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/Library/Application Support/SSH-TunelApp');
      }
    }

    if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ??
          Platform.environment['LOCALAPPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData${Platform.pathSeparator}SSH-TunelApp');
      }
    }

    if (Platform.isLinux) {
      final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
      if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
        return Directory('$xdgConfigHome/SSH-TunelApp');
      }

      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/.config/SSH-TunelApp');
      }
    }

    final fallback = Directory.current.path;
    return Directory('$fallback/.ssh_tunnelapp');
  }

  @override
  void dispose() {
    _saveTimer?.cancel();

    for (final entry in _configListeners.entries) {
      final cfg = _configurations.where((c) => c.id == entry.key).toList();
      if (cfg.isNotEmpty) {
        cfg.first.removeListener(entry.value);
      }
    }
    for (final entry in _connectionListeners.entries) {
      final cfg = _configurations.where((c) => c.id == entry.key).toList();
      if (cfg.isNotEmpty) {
        cfg.first.connection.removeListener(entry.value);
      }
    }

    for (final cfg in _configurations) {
      cfg.connection.dispose();
      cfg.dispose();
    }

    super.dispose();
  }
}

class SSHConfiguration extends ChangeNotifier {
  SSHConfiguration({required this.name, required String defaultLocalPort})
    : id = _nextId(),
      connection = SSHConnectionController(defaultLocalPort: defaultLocalPort);

  SSHConfiguration._({
    required this.id,
    required this.name,
    required this.connection,
  });

  factory SSHConfiguration.fromJson(Map<String, dynamic> json) {
    final connectionJson = json['connection'];
    final connection = connectionJson is Map<String, dynamic>
        ? SSHConnectionController.fromSnapshot(connectionJson)
        : connectionJson is Map
        ? SSHConnectionController.fromSnapshot(
            Map<String, dynamic>.from(connectionJson),
          )
        : SSHConnectionController(defaultLocalPort: '5901');

    return SSHConfiguration._(
      id: (json['id'] as String?) ?? _nextId(),
      name: (json['name'] as String?) ?? 'Connexió',
      connection: connection,
    );
  }

  final String id;
  String name;
  final SSHConnectionController connection;

  void setName(String value) {
    if (name == value) {
      return;
    }
    name = value;
    notifyListeners();
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'connection': connection.snapshot()};
  }
}

class PortForwardRule {
  PortForwardRule({
    required this.id,
    required this.name,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
  });

  factory PortForwardRule.createDefault(String name, String localPort) {
    return PortForwardRule(
      id: _nextId(),
      name: name,
      localPort: localPort,
      remoteHost: 'localhost',
      remotePort: '5900',
    );
  }

  factory PortForwardRule.fromJson(Map<String, dynamic> json) {
    return PortForwardRule(
      id: (json['id'] as String?) ?? _nextId(),
      name: (json['name'] as String?) ?? '',
      localPort: (json['localPort'] as String?) ?? '',
      remoteHost: (json['remoteHost'] as String?) ?? 'localhost',
      remotePort: (json['remotePort'] as String?) ?? '',
    );
  }

  final String id;
  String name;
  String localPort;
  String remoteHost;
  String remotePort;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'localPort': localPort,
      'remoteHost': remoteHost,
      'remotePort': remotePort,
    };
  }
}

class SSHConnectionController extends ChangeNotifier {
  SSHConnectionController({required String defaultLocalPort})
    : forwardRules = [
        PortForwardRule.createDefault('Regla 1', defaultLocalPort),
      ];

  SSHConnectionController.fromSnapshot(Map<String, dynamic> snapshot)
    : host = (snapshot['host'] as String?) ?? '',
      user = (snapshot['user'] as String?) ?? '',
      sshPort = (snapshot['sshPort'] as String?) ?? '',
      keyPath = _normalizeKeyPath((snapshot['keyPath'] as String?) ?? ''),
      autoReconnect = (snapshot['autoReconnect'] as bool?) ?? false,
      forwardRules = _parseRules(snapshot['forwardRules']);

  String status = 'Aturat';
  bool isRunning = false;

  String host = '';
  String user = '';
  String sshPort = '';
  String keyPath = '';
  List<PortForwardRule> forwardRules;

  bool autoReconnect = false;
  String logText = '';

  static String _normalizeKeyPath(String value) {
    if (Platform.isWindows) {
      return _normalizeWindowsKeyPath(value);
    }
    if (!(Platform.isMacOS || Platform.isLinux)) {
      return value;
    }
    if (value == r'$HOME') {
      return '~';
    }
    if (value.startsWith(r'$HOME/')) {
      return '~/${value.substring(r'$HOME/'.length)}';
    }
    if (value.startsWith('\$HOME\\')) {
      return '~\\${value.substring('\$HOME\\'.length)}';
    }
    return value;
  }

  static String _normalizeWindowsKeyPath(String value) {
    final home = _windowsHomePath();
    if (home == null || home.isEmpty) {
      return value;
    }

    if (value == '~') {
      return home;
    }
    if (_startsWithIgnoreCase(value, '~/')) {
      return _joinWindowsHome(home, value.substring(2));
    }
    if (_startsWithIgnoreCase(value, '~\\')) {
      return _joinWindowsHome(home, value.substring(2));
    }

    if (_startsWithIgnoreCase(value, r'%USERPROFILE%/')) {
      return _joinWindowsHome(home, value.substring(r'%USERPROFILE%/'.length));
    }
    if (_startsWithIgnoreCase(value, '%USERPROFILE%\\')) {
      return _joinWindowsHome(home, value.substring('%USERPROFILE%\\'.length));
    }
    if (_startsWithIgnoreCase(value, r'%HOMEDRIVE%%HOMEPATH%/')) {
      return _joinWindowsHome(
        home,
        value.substring(r'%HOMEDRIVE%%HOMEPATH%/'.length),
      );
    }
    if (_startsWithIgnoreCase(value, '%HOMEDRIVE%%HOMEPATH%\\')) {
      return _joinWindowsHome(
        home,
        value.substring('%HOMEDRIVE%%HOMEPATH%\\'.length),
      );
    }

    if (_startsWithIgnoreCase(value, r'$HOME/')) {
      return _joinWindowsHome(home, value.substring(r'$HOME/'.length));
    }
    if (_startsWithIgnoreCase(value, '\$HOME\\')) {
      return _joinWindowsHome(home, value.substring('\$HOME\\'.length));
    }

    if (_equalsIgnoreCase(value, r'%USERPROFILE%') ||
        _equalsIgnoreCase(value, r'%HOMEDRIVE%%HOMEPATH%') ||
        _equalsIgnoreCase(value, r'$HOME')) {
      return home;
    }

    return value;
  }

  static String? _windowsHomePath() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }
    final drive = Platform.environment['HOMEDRIVE'];
    final path = Platform.environment['HOMEPATH'];
    if (drive != null && drive.isNotEmpty && path != null && path.isNotEmpty) {
      return '$drive$path';
    }
    return null;
  }

  static String _joinWindowsHome(String home, String suffix) {
    if (suffix.isEmpty) {
      return home;
    }
    final cleanSuffix = suffix.replaceAll('/', '\\');
    if (home.endsWith('\\') || home.endsWith('/')) {
      return '$home$cleanSuffix';
    }
    return '$home\\$cleanSuffix';
  }

  static bool _startsWithIgnoreCase(String value, String prefix) {
    if (value.length < prefix.length) {
      return false;
    }
    return value.substring(0, prefix.length).toLowerCase() ==
        prefix.toLowerCase();
  }

  static bool _equalsIgnoreCase(String a, String b) {
    return a.toLowerCase() == b.toLowerCase();
  }

  static final String _sshPath = _platformCommand(
    'ssh',
    macOSPath: '/usr/bin/ssh',
    linuxPaths: const ['/usr/bin/ssh', '/bin/ssh'],
    windowsPaths: const [r'C:\Windows\System32\OpenSSH\ssh.exe'],
  );
  static final String _lsofPath = _platformCommand(
    'lsof',
    macOSPath: '/usr/sbin/lsof',
    linuxPaths: const ['/usr/bin/lsof', '/bin/lsof'],
  );
  static final String _ssPath = _platformCommand(
    'ss',
    macOSPath: 'ss',
    linuxPaths: const ['/usr/bin/ss', '/bin/ss', '/usr/sbin/ss'],
  );
  static final String _psPath = _platformCommand(
    'ps',
    macOSPath: '/bin/ps',
    linuxPaths: const ['/usr/bin/ps', '/bin/ps'],
  );
  static final String _killPath = _platformCommand(
    'kill',
    macOSPath: '/bin/kill',
    linuxPaths: const ['/usr/bin/kill', '/bin/kill'],
  );
  static final String _netstatPath = _platformCommand(
    'netstat',
    macOSPath: '/usr/sbin/netstat',
    linuxPaths: const ['/usr/bin/netstat', '/bin/netstat'],
    windowsPaths: const [r'C:\Windows\System32\netstat.exe'],
  );
  static final String _taskkillPath = _platformCommand(
    'taskkill',
    macOSPath: 'taskkill',
    windowsPaths: const [r'C:\Windows\System32\taskkill.exe'],
  );
  static final String _tasklistPath = _platformCommand(
    'tasklist',
    macOSPath: 'tasklist',
    windowsPaths: const [r'C:\Windows\System32\tasklist.exe'],
  );
  static final String _powershellPath = _platformCommand(
    'powershell',
    macOSPath: 'powershell',
    windowsPaths: const [
      r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
    ],
  );
  static final String _keyscanPath = _platformCommand(
    'ssh-keyscan',
    macOSPath: '/usr/bin/ssh-keyscan',
    linuxPaths: const ['/usr/bin/ssh-keyscan', '/bin/ssh-keyscan'],
    windowsPaths: const [r'C:\Windows\System32\OpenSSH\ssh-keyscan.exe'],
  );

  Process? _process;
  Timer? _statusTimer;
  Timer? _reconnectTimer;
  bool _statusUpdateInProgress = false;
  int _failures = 0;
  bool _stopRequested = false;
  bool _didAttemptKnownHostsFix = false;
  int? _externalMatchingPid;

  Map<String, dynamic> snapshot() {
    return {
      'host': host,
      'user': user,
      'sshPort': sshPort,
      'keyPath': keyPath,
      'forwardRules': forwardRules.map((e) => e.toJson()).toList(),
      'autoReconnect': autoReconnect,
    };
  }

  void setHost(String value) {
    if (host == value) {
      return;
    }
    host = value;
    notifyListeners();
  }

  void setUser(String value) {
    if (user == value) {
      return;
    }
    user = value;
    notifyListeners();
  }

  void setSshPort(String value) {
    if (sshPort == value) {
      return;
    }
    sshPort = value;
    notifyListeners();
  }

  void setKeyPath(String value) {
    final normalized = _normalizeKeyPath(value);
    if (keyPath == normalized) {
      return;
    }
    keyPath = normalized;
    notifyListeners();
  }

  void setAutoReconnect(bool value) {
    if (autoReconnect == value) {
      return;
    }
    autoReconnect = value;
    notifyListeners();
  }

  void updateRuleName(String id, String value) {
    final idx = forwardRules.indexWhere((r) => r.id == id);
    if (idx < 0 || forwardRules[idx].name == value) {
      return;
    }
    forwardRules[idx].name = value;
    notifyListeners();
  }

  void updateRuleLocalPort(String id, String value) {
    final idx = forwardRules.indexWhere((r) => r.id == id);
    if (idx < 0 || forwardRules[idx].localPort == value) {
      return;
    }
    forwardRules[idx].localPort = value;
    notifyListeners();
  }

  void updateRuleRemoteHost(String id, String value) {
    final idx = forwardRules.indexWhere((r) => r.id == id);
    if (idx < 0 || forwardRules[idx].remoteHost == value) {
      return;
    }
    forwardRules[idx].remoteHost = value;
    notifyListeners();
  }

  void updateRuleRemotePort(String id, String value) {
    final idx = forwardRules.indexWhere((r) => r.id == id);
    if (idx < 0 || forwardRules[idx].remotePort == value) {
      return;
    }
    forwardRules[idx].remotePort = value;
    notifyListeners();
  }

  void clearLog() {
    logText = '';
    notifyListeners();
  }

  void addForwardRule() {
    if (isRunning) {
      return;
    }

    forwardRules.add(
      PortForwardRule(
        id: _nextId(),
        name: _suggestedRuleName(),
        localPort: _suggestedLocalPort(),
        remoteHost: 'localhost',
        remotePort: '5900',
      ),
    );
    notifyListeners();
  }

  void removeForwardRule(String id) {
    if (isRunning || forwardRules.length == 1) {
      return;
    }

    forwardRules = forwardRules.where((rule) => rule.id != id).toList();
    notifyListeners();
  }

  Future<void> checkInitialState() async {
    final state = await _detectCurrentState();
    switch (state.type) {
      case DetectedStateType.activeOursControlMaster:
        isRunning = true;
        status = 'Actiu (localhost:${_localPortsSummary()})';
        _startTimer();
        break;
      case DetectedStateType.activeMatchesConfigByPid:
        _externalMatchingPid = state.pid;
        isRunning = true;
        status = 'Actiu (localhost:${_localPortsSummary()})';
        _startTimer();
        break;
      case DetectedStateType.portUsedByOther:
        _externalMatchingPid = null;
        isRunning = false;
        status = 'Error: port local ocupat (${_localPortsSummary()})';
        _stopTimer();
        break;
      case DetectedStateType.stopped:
        _externalMatchingPid = null;
        isRunning = false;
        status = 'Aturat';
        _stopTimer();
        break;
    }
    notifyListeners();
  }

  Future<void> start() async {
    _stopRequested = false;
    _failures = 0;
    _didAttemptKnownHostsFix = false;
    _externalMatchingPid = null;
    logText = '';
    status = 'Connectant…';
    notifyListeners();
    await _startInternal();
  }

  Future<void> stop() async {
    _stopRequested = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final exited = await _sshControlExit();
    if (exited) {
      _process?.kill(ProcessSignal.sigterm);
      _process = null;
      _externalMatchingPid = null;
      _stopTimer();
      isRunning = false;
      status = 'Aturat';
      notifyListeners();
      return;
    }

    if (_externalMatchingPid != null) {
      await _killPid(_externalMatchingPid!);
      _externalMatchingPid = null;
    }

    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    _stopTimer();
    isRunning = false;
    status = 'Aturat';
    notifyListeners();
  }

  String get statusLabel {
    if (status.startsWith('Actiu')) {
      return 'Actiu';
    }
    if (status.startsWith('Connectant') ||
        status.startsWith('Reintentant') ||
        status.startsWith('Afegint host')) {
      return 'Connectant';
    }
    if (status.startsWith('Aturat')) {
      return 'Aturat';
    }
    return 'Error';
  }

  Color get statusColor {
    if (status.startsWith('Actiu')) {
      return CupertinoColors.systemGreen;
    }
    if (status.startsWith('Connectant') ||
        status.startsWith('Reintentant') ||
        status.startsWith('Afegint host')) {
      return CupertinoColors.systemOrange;
    }
    if (status.startsWith('Aturat')) {
      return CupertinoColors.systemRed;
    }
    return CupertinoColors.secondaryLabel;
  }

  bool get _supportsControlMaster => !Platform.isWindows;

  Future<void> _startInternal() async {
    if (_process != null) {
      return;
    }

    if (forwardRules.isEmpty) {
      status = 'Error: cap regla de port definida';
      notifyListeners();
      return;
    }

    final parsed = <({int local, String remoteHost, int remotePort})>[];
    for (final rule in forwardRules) {
      final lp = int.tryParse(rule.localPort);
      final rp = int.tryParse(rule.remotePort);
      if (lp == null ||
          rp == null ||
          lp < 1 ||
          lp > 65535 ||
          rp < 1 ||
          rp > 65535) {
        status = 'Error: ports invàlids';
        notifyListeners();
        return;
      }
      parsed.add((local: lp, remoteHost: rule.remoteHost, remotePort: rp));
    }

    final detected = await _detectCurrentState();
    switch (detected.type) {
      case DetectedStateType.activeOursControlMaster:
        _externalMatchingPid = null;
        isRunning = true;
        status = 'Actiu (localhost:${_localPortsSummary()})';
        _startTimer();
        notifyListeners();
        return;
      case DetectedStateType.activeMatchesConfigByPid:
        _externalMatchingPid = detected.pid;
        isRunning = true;
        status = 'Actiu (localhost:${_localPortsSummary()})';
        _startTimer();
        notifyListeners();
        return;
      case DetectedStateType.portUsedByOther:
        _externalMatchingPid = null;
        isRunning = false;
        status = 'Error: port local ocupat (${_localPortsSummary()})';
        _appendLog('[error] Local port in use by another process.');
        _stopTimer();
        notifyListeners();
        return;
      case DetectedStateType.stopped:
        break;
    }

    status = 'Connectant…';
    notifyListeners();

    final args = <String>['-N', '-T', '-i', keyPath, '-p', sshPort];

    for (final item in parsed) {
      args.addAll([
        '-L',
        '${item.local}:${item.remoteHost}:${item.remotePort}',
      ]);
    }

    args.addAll([
      '-o',
      'ExitOnForwardFailure=yes',
      '-o',
      'ServerAliveInterval=10',
      '-o',
      'ServerAliveCountMax=3',
      '-o',
      'ConnectTimeout=5',
      '-o',
      'ConnectionAttempts=1',
      '-o',
      'BatchMode=yes',
      '-o',
      'StrictHostKeyChecking=accept-new',
    ]);

    if (_supportsControlMaster) {
      args.addAll([
        '-o',
        'ControlMaster=yes',
        '-o',
        'ControlPersist=yes',
        '-o',
        'ControlPath=$_controlSocketPath',
      ]);
    }

    args.add(_sshTarget());

    Process p;
    try {
      p = await Process.start(_sshPath, args);
    } catch (_) {
      _appendLog('[error] Cannot execute ssh');
      status = 'Error: no puc executar ssh';
      notifyListeners();
      if (autoReconnect && !_stopRequested) {
        _scheduleReconnect();
      }
      return;
    }

    _process = p;
    isRunning = true;
    _startTimer();
    notifyListeners();

    p.stdout.transform(utf8.decoder).listen(_appendLog);
    p.stderr.transform(utf8.decoder).listen(_appendLog);

    unawaited(
      p.exitCode.then((code) async {
        if (_process == p) {
          _process = null;
        }
        isRunning = false;
        _stopTimer();

        if (_stopRequested) {
          status = 'Aturat';
          notifyListeners();
          return;
        }

        if (_isUnknownHostFailure(logText) && !_didAttemptKnownHostsFix) {
          _didAttemptKnownHostsFix = true;
          status = 'Afegint host a known_hosts…';
          notifyListeners();

          final ok = await _addHostToKnownHosts();
          if (ok) {
            _appendLog('[info] Added host key to ~/.ssh/known_hosts');
            status = 'Connectant…';
            notifyListeners();
            await _startInternal();
            return;
          }

          _appendLog('[error] Failed to add host key to ~/.ssh/known_hosts');
          status = 'Error: no puc afegir host a known_hosts';
          notifyListeners();
          return;
        }

        final detectedState = await _detectCurrentState();
        switch (detectedState.type) {
          case DetectedStateType.activeOursControlMaster:
            _externalMatchingPid = null;
            isRunning = true;
            status = 'Actiu (localhost:${_localPortsSummary()})';
            _startTimer();
            notifyListeners();
            return;
          case DetectedStateType.activeMatchesConfigByPid:
            _externalMatchingPid = detectedState.pid;
            isRunning = true;
            status = 'Actiu (localhost:${_localPortsSummary()})';
            _startTimer();
            notifyListeners();
            return;
          case DetectedStateType.portUsedByOther:
            _externalMatchingPid = null;
            status = 'Error: port local ocupat (${_localPortsSummary()})';
            notifyListeners();
            return;
          case DetectedStateType.stopped:
            break;
        }

        final kind = _classifyFailure(logText);

        switch (kind) {
          case FailureKind.addressInUse:
          case FailureKind.authOrKey:
          case FailureKind.config:
            status = _statusFor(kind);
            notifyListeners();
            return;
          case FailureKind.unknownHost:
            status = 'Error: host key';
            notifyListeners();
            if (autoReconnect) {
              _scheduleReconnect();
            }
            return;
          case FailureKind.transient:
          case FailureKind.other:
            status = 'Error (ssh $code)';
            notifyListeners();
            if (autoReconnect) {
              _scheduleReconnect();
            }
            return;
        }
      }),
    );
  }

  Future<DetectedState> _detectCurrentState() async {
    if (await _isOurTunnelActive()) {
      return const DetectedState.activeOursControlMaster();
    }

    for (final rule in forwardRules) {
      final lp = int.tryParse(rule.localPort);
      if (lp == null || lp < 1 || lp > 65535) {
        continue;
      }

      final pid = await _lsofListeningPid(lp);
      if (pid == null) {
        if (await _isPortListening(lp)) {
          return const DetectedState.portUsedByOther();
        }
        continue;
      }

      final cmd = await _psCommandLine(pid);
      if (_matchesOurTunnelCommandLine(cmd)) {
        return DetectedState.activeMatchesConfigByPid(pid);
      }
      return const DetectedState.portUsedByOther();
    }

    return const DetectedState.stopped();
  }

  Future<bool> _isOurTunnelActive() async {
    if (!_supportsControlMaster) {
      return false;
    }

    final res = await _runCommand(_sshPath, [
      '-S',
      _controlSocketPath,
      '-p',
      sshPort,
      '-O',
      'check',
      _sshTarget(),
    ]);
    return res.exitCode == 0;
  }

  Future<bool> _sshControlExit() async {
    if (!_supportsControlMaster) {
      return false;
    }

    final res = await _runCommand(_sshPath, [
      '-S',
      _controlSocketPath,
      '-p',
      sshPort,
      '-O',
      'exit',
      _sshTarget(),
    ]);
    return res.exitCode == 0;
  }

  Future<int?> _lsofListeningPid(int port) async {
    if (Platform.isWindows) {
      return _windowsListeningPid(port);
    }

    final res = await _runCommand(_lsofPath, [
      '-nP',
      '-iTCP:$port',
      '-sTCP:LISTEN',
      '-Fp',
    ]);

    if (res.exitCode != 0) {
      return null;
    }

    final lines = res.stdout.split('\n');
    for (final line in lines) {
      if (line.startsWith('p')) {
        return int.tryParse(line.substring(1));
      }
    }

    return null;
  }

  Future<int?> _windowsListeningPid(int port) async {
    final res = await _runCommand(_netstatPath, ['-ano', '-p', 'tcp']);
    if (res.exitCode != 0 || res.stdout.trim().isEmpty) {
      return null;
    }

    for (final rawLine in res.stdout.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final cols = line.split(RegExp(r'\s+'));
      if (cols.length < 5) {
        continue;
      }

      final proto = cols[0].toUpperCase();
      final localEndpoint = cols[1];
      final state = cols[3].toUpperCase();
      final pid = int.tryParse(cols[4]);

      if (proto != 'TCP' || state != 'LISTENING' || pid == null) {
        continue;
      }
      if (_endpointHasPort(localEndpoint, port)) {
        return pid;
      }
    }

    return null;
  }

  Future<String> _psCommandLine(int pid) async {
    if (Platform.isWindows) {
      final script =
          '(Get-CimInstance Win32_Process -Filter "ProcessId = $pid").CommandLine';
      final fromPowerShell = await _runCommand(_powershellPath, [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]);
      if (fromPowerShell.exitCode == 0) {
        final commandLine = fromPowerShell.stdout.trim();
        if (commandLine.isNotEmpty) {
          return commandLine;
        }
      }

      final fromTasklist = await _runCommand(_tasklistPath, [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      if (fromTasklist.exitCode == 0) {
        final tasklistOutput = fromTasklist.stdout.trim();
        final line = tasklistOutput.isEmpty
            ? ''
            : tasklistOutput.split('\n').first;
        if (line.isNotEmpty && !line.contains('No tasks are running')) {
          return line;
        }
      }
      return '';
    }

    final res = await _runCommand(_psPath, ['-p', '$pid', '-o', 'command=']);
    return res.stdout.trim();
  }

  bool _matchesOurTunnelCommandLine(String cmd) {
    if (Platform.isWindows) {
      final lower = cmd.toLowerCase();
      if (!lower.contains('ssh.exe') && !lower.contains('\\ssh')) {
        return false;
      }
      // Verify the command line matches our specific tunnel configuration so
      // that unrelated ssh.exe processes (e.g. Git, VS Code remote) are not
      // mistaken for our tunnel.
      final target = '$user@$host';
      final portOpt = '-p $sshPort';
      if (!cmd.contains(target) || !cmd.contains(portOpt)) {
        return false;
      }
      for (final rule in forwardRules) {
        final forward =
            '-L ${rule.localPort}:${rule.remoteHost}:${rule.remotePort}';
        if (!cmd.contains(forward)) {
          return false;
        }
      }
      return true;
    }

    final target = '$user@$host';
    final portOpt = '-p $sshPort';

    if (!cmd.contains('ssh')) {
      return false;
    }
    if (!cmd.contains(target) || !cmd.contains(portOpt)) {
      return false;
    }

    for (final rule in forwardRules) {
      final forward =
          '-L ${rule.localPort}:${rule.remoteHost}:${rule.remotePort}';
      if (!cmd.contains(forward)) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _killPid(int pid) async {
    if (Platform.isWindows) {
      final res = await _runCommand(_taskkillPath, [
        '/PID',
        '$pid',
        '/T',
        '/F',
      ]);
      return res.exitCode == 0;
    }

    try {
      if (Process.killPid(pid, ProcessSignal.sigterm)) {
        return true;
      }
    } catch (_) {
      // Fallback to external command for environments where killPid fails.
    }

    final res = await _runCommand(_killPath, ['-TERM', '$pid']);
    return res.exitCode == 0;
  }

  Future<bool> _isPortListening(int port) async {
    if (Platform.isLinux) {
      final res = await _runCommand(_ssPath, ['-lntH']);
      if (res.exitCode != 0 || res.stdout.trim().isEmpty) {
        return false;
      }

      for (final line in res.stdout.split('\n')) {
        final cols = line.trim().split(RegExp(r'\s+'));
        if (cols.length < 2) {
          continue;
        }
        final localEndpoint = cols[cols.length - 2];
        if (_endpointHasPort(localEndpoint, port)) {
          return true;
        }
      }
      return false;
    }

    if (Platform.isWindows) {
      final pid = await _windowsListeningPid(port);
      return pid != null;
    }

    return false;
  }

  bool _endpointHasPort(String endpoint, int port) {
    return endpoint.endsWith(':$port') || endpoint.endsWith(']:$port');
  }

  String? _homePath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return home;
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }
    return null;
  }

  String _joinPath(String base, String leaf) {
    final separator = Platform.pathSeparator;
    if (base.endsWith('/') || base.endsWith(r'\')) {
      return '$base$leaf';
    }
    return '$base$separator$leaf';
  }

  String _socketPathForDigest(String digest) {
    final home = _homePath() ?? Directory.current.path;
    final sshDir = _joinPath(home, '.ssh');
    final fileName = Platform.isWindows
        ? 'tunnelctl_$digest.ctl'
        : 'tunnelctl_$digest.sock';
    return _joinPath(sshDir, fileName);
  }

  String _knownHostsPath(String home) {
    final sshDir = _joinPath(home, '.ssh');
    return _joinPath(sshDir, 'known_hosts');
  }

  String _sshDirectoryPath(String home) {
    return _joinPath(home, '.ssh');
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _failures += 1;
    final delay = min(pow(2, _failures).toInt(), 60);
    status = 'Reintentant en ${delay}s…';
    notifyListeners();

    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_stopRequested) {
        return;
      }
      unawaited(_startInternal());
    });
  }

  void _startTimer() {
    if (_statusTimer != null) {
      return;
    }

    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_updateStatus());
    });
  }

  void _stopTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  Future<void> _updateStatus() async {
    if (_statusUpdateInProgress) {
      return;
    }

    if (_isInTransientState() &&
        (_process != null || _reconnectTimer != null)) {
      return;
    }

    _statusUpdateInProgress = true;
    try {
      final state = await _detectCurrentState();
      switch (state.type) {
        case DetectedStateType.activeOursControlMaster:
          _externalMatchingPid = null;
          isRunning = true;
          status = 'Actiu (localhost:${_localPortsSummary()})';
          break;
        case DetectedStateType.activeMatchesConfigByPid:
          _externalMatchingPid = state.pid;
          isRunning = true;
          status = 'Actiu (localhost:${_localPortsSummary()})';
          break;
        case DetectedStateType.portUsedByOther:
          _externalMatchingPid = null;
          isRunning = false;
          status = 'Error: port local ocupat (${_localPortsSummary()})';
          break;
        case DetectedStateType.stopped:
          _externalMatchingPid = null;
          isRunning = false;
          status = 'Aturat';
          break;
      }
      notifyListeners();
    } finally {
      _statusUpdateInProgress = false;
    }
  }

  bool _isInTransientState() {
    return status.startsWith('Connectant') ||
        status.startsWith('Afegint host') ||
        status.startsWith('Reintentant');
  }

  FailureKind _classifyFailure(String text) {
    final s = text.toLowerCase();

    if (s.contains('the authenticity of host') ||
        s.contains('are you sure you want to continue connecting') ||
        s.contains('host key verification failed')) {
      return FailureKind.unknownHost;
    }

    if (s.contains('address already in use') ||
        s.contains('cannot listen to port') ||
        s.contains('could not request local forwarding')) {
      return FailureKind.addressInUse;
    }

    if (s.contains('permission denied') ||
        s.contains('private key file') ||
        (s.contains('no such file or directory') && s.contains('.ssh')) ||
        s.contains('bad permissions') ||
        (s.contains('identity file') && s.contains('not accessible'))) {
      return FailureKind.authOrKey;
    }

    if (s.contains('bad configuration option') ||
        s.contains('unknown option')) {
      return FailureKind.config;
    }

    if (s.contains('connection timed out') ||
        s.contains('operation timed out') ||
        s.contains('connection reset by peer') ||
        s.contains('broken pipe') ||
        s.contains('connection refused') ||
        s.contains('network is unreachable') ||
        s.contains('no route to host')) {
      return FailureKind.transient;
    }

    return FailureKind.other;
  }

  String _statusFor(FailureKind kind) {
    switch (kind) {
      case FailureKind.addressInUse:
        return 'Error: port local ocupat (${_localPortsSummary()})';
      case FailureKind.authOrKey:
        return 'Error: autenticació/clau';
      case FailureKind.config:
        return 'Error: configuració ssh';
      default:
        return 'Error';
    }
  }

  bool _isUnknownHostFailure(String text) {
    final s = text.toLowerCase();
    return s.contains('the authenticity of host') ||
        s.contains('are you sure you want to continue connecting') ||
        s.contains('host key verification failed');
  }

  Future<bool> _addHostToKnownHosts() async {
    final port = int.tryParse(sshPort);
    if (port == null) {
      return false;
    }

    final home = _homePath();
    if (home == null || home.isEmpty) {
      return false;
    }

    final sshDir = Directory(_sshDirectoryPath(home));
    final knownHosts = File(_knownHostsPath(home));

    try {
      await sshDir.create(recursive: true);

      final scan = await _runCommand(_keyscanPath, ['-p', '$port', host]);
      if (scan.exitCode != 0) {
        return false;
      }

      final text = scan.stdout.trim();
      if (text.isEmpty) {
        return false;
      }

      if (!await knownHosts.exists()) {
        await knownHosts.create(recursive: true);
      }

      await knownHosts.writeAsString('$text\n', mode: FileMode.append);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<CommandResult> _runCommand(String exe, List<String> args) async {
    try {
      final result = await Process.run(exe, args);
      return CommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } catch (e) {
      return CommandResult(exitCode: -1, stdout: '', stderr: '$e');
    }
  }

  void _appendLog(String raw) {
    final cleaned = raw.replaceAll('\r', '');
    final lines = cleaned
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return;
    }

    if (logText.isNotEmpty) {
      logText = '$logText\n';
    }
    logText = '$logText${lines.join('\n')}';
    notifyListeners();
  }

  String _localPortsSummary() {
    return forwardRules.map((r) => r.localPort).join(',');
  }

  String _suggestedLocalPort() {
    const base = 5901;
    final used = forwardRules
        .map((r) => int.tryParse(r.localPort))
        .whereType<int>()
        .toSet();

    var port = base;
    while (used.contains(port)) {
      port += 1;
    }
    return '$port';
  }

  String _suggestedRuleName() {
    const base = 'Regla';
    final used = forwardRules.map((r) => r.name.trim()).toSet();
    var idx = 1;
    while (used.contains('$base $idx')) {
      idx += 1;
    }
    return '$base $idx';
  }

  String _sshTarget() => '$user@$host';

  String get _controlSocketPath {
    final rulesKey =
        forwardRules
            .map((r) => 'L${r.localPort}->${r.remoteHost}:${r.remotePort}')
            .toList()
          ..sort();

    final base = '$user@$host:$sshPort|${rulesKey.join('|')}';
    final digest = _stableShortHash(base);
    return _socketPathForDigest(digest);
  }

  String _stableShortHash(String input) {
    var hash = BigInt.parse('14695981039346656037');
    final prime = BigInt.from(1099511628211);
    final mask = (BigInt.one << 64) - BigInt.one;

    for (final byte in utf8.encode(input)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _reconnectTimer?.cancel();
    _process?.kill(ProcessSignal.sigterm);
    super.dispose();
  }

  static List<PortForwardRule> _parseRules(dynamic raw) {
    if (raw is! List) {
      return [PortForwardRule.createDefault('Regla 1', '5901')];
    }

    final parsed = <PortForwardRule>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        parsed.add(PortForwardRule.fromJson(item));
      } else if (item is Map) {
        parsed.add(PortForwardRule.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    if (parsed.isEmpty) {
      return [PortForwardRule.createDefault('Regla 1', '5901')];
    }

    return parsed;
  }

  static String _platformCommand(
    String command, {
    required String macOSPath,
    List<String> linuxPaths = const [],
    List<String> windowsPaths = const [],
  }) {
    if (Platform.isMacOS) {
      return macOSPath;
    }

    if (Platform.isLinux) {
      for (final path in linuxPaths) {
        if (File(path).existsSync()) {
          return path;
        }
      }
    }

    if (Platform.isWindows) {
      // 1. Check known fixed paths (locale-independent, e.g. System32\OpenSSH).
      for (final path in windowsPaths) {
        if (File(path).existsSync()) {
          return path;
        }
      }

      // 2. Check under %ProgramFiles% and %ProgramFiles(x86)%, which are
      //    locale-aware env vars (e.g. "Archivos de programa" on Spanish
      //    Windows) — more reliable than hardcoding "C:\Program Files".
      final programFilesDirs = [
        Platform.environment['ProgramFiles'],
        Platform.environment['ProgramFiles(x86)'],
      ].whereType<String>().where((d) => d.isNotEmpty);

      for (final dir in programFilesDirs) {
        for (final sub in [r'OpenSSH', r'OpenSSH-Win64']) {
          final candidate = '$dir\\$sub\\$command.exe';
          if (File(candidate).existsSync()) {
            return candidate;
          }
        }
      }

      // 3. Fall back to resolving via where.exe so that PATH-installed OpenSSH
      //    (e.g. Git for Windows, winget installs) is found even when not at a
      //    known fixed path.
      try {
        final result = Process.runSync(
          r'C:\Windows\System32\where.exe',
          [command],
        );
        if (result.exitCode == 0) {
          final first =
              result.stdout
                  .toString()
                  .split('\n')
                  .map((l) => l.trim())
                  .firstWhere((l) => l.isNotEmpty, orElse: () => '');
          if (first.isNotEmpty) {
            return first;
          }
        }
      } catch (_) {
        // where.exe not available or failed — fall through to bare name.
      }
    }

    return command;
  }
}

class DetectedState {
  const DetectedState._(this.type, this.pid);

  const DetectedState.activeOursControlMaster()
    : this._(DetectedStateType.activeOursControlMaster, null);

  const DetectedState.activeMatchesConfigByPid(int pid)
    : this._(DetectedStateType.activeMatchesConfigByPid, pid);

  const DetectedState.portUsedByOther()
    : this._(DetectedStateType.portUsedByOther, null);

  const DetectedState.stopped() : this._(DetectedStateType.stopped, null);

  final DetectedStateType type;
  final int? pid;
}

enum DetectedStateType {
  activeOursControlMaster,
  activeMatchesConfigByPid,
  portUsedByOther,
  stopped,
}

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

enum FailureKind {
  unknownHost,
  addressInUse,
  authOrKey,
  config,
  transient,
  other,
}

final Random _idRandom = Random();

String _nextId() {
  final micros = DateTime.now().microsecondsSinceEpoch;
  final rand = _idRandom.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return '$micros-$rand';
}

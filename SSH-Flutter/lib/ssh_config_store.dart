import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'l10n.dart';
import 'ssh_connection_controller.dart';

/// What to do with open tunnels when the app quits.
enum QuitBehavior { ask, closeTunnels, keepTunnels }

class SSHConfigStore extends ChangeNotifier {
  /// [saveDirectory] overrides the platform settings folder (tests).
  /// With [observeSystem] false there is no wake detection or launch refresh.
  SSHConfigStore({this.saveDirectory, this.observeSystem = true});

  final Directory? saveDirectory;
  final bool observeSystem;

  final List<SSHConfiguration> _configurations = [];
  File? _settingsFile;
  QuitBehavior _quitBehavior = QuitBehavior.ask;

  QuitBehavior get quitBehavior => _quitBehavior;

  set quitBehavior(QuitBehavior value) {
    if (_quitBehavior == value) return;
    _quitBehavior = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  List<SSHConfiguration> get runningConfigurations =>
      _configurations.where((c) => c.connection.isRunning).toList();

  static String defaultName(int index) => l10n.defaultConfigName(index);
  final List<VoidCallback> _detachers = [];

  String? selectedId;
  File? _saveFile;
  Timer? _saveTimer;
  String? _lastSavedJson;
  WakeDetector? _wakeDetector;

  List<SSHConfiguration> get configurations =>
      List.unmodifiable(_configurations);

  SSHConfiguration? get selectedConfiguration {
    for (final cfg in _configurations) {
      if (cfg.id == selectedId) return cfg;
    }
    return null;
  }

  Future<void> initialize() async {
    final appSupportDir = saveDirectory ?? await _appSupportDirectory();
    await appSupportDir.create(recursive: true);
    _saveFile = File('${appSupportDir.path}/configs.json');
    _settingsFile = File('${appSupportDir.path}/settings.json');
    await _loadSettings();
    var needsIdMigrationSave = false;

    if (await _saveFile!.exists()) {
      try {
        final raw = await _saveFile!.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final itemMap = Map<String, dynamic>.from(item);
              needsIdMigrationSave =
                  needsIdMigrationSave || _configurationNeedsMigration(itemMap);
              _configurations.add(SSHConfiguration.fromJson(itemMap));
            }
          }
        }
        _lastSavedJson = raw;
      } catch (_) {
        // Keep the unreadable file untouched: back it up before the first save.
        await _backupUnreadable(_saveFile!);
      }
    }

    selectedId = _configurations.isEmpty ? null : _configurations.first.id;
    _attachObservers();
    notifyListeners();

    if (needsIdMigrationSave && _configurations.isNotEmpty) {
      await _save();
    }

    if (!observeSystem) return;

    // Show the real state of every tunnel (they survive app restarts via ControlPersist).
    for (final cfg in _configurations) {
      unawaited(cfg.connection.refresh());
    }

    _wakeDetector = WakeDetector(
      onWake: () {
        for (final cfg in _configurations) {
          cfg.connection.systemDidWake();
        }
      },
    )..start();
  }

  void selectConfiguration(String id) {
    if (selectedId == id) return;
    selectedId = id;
    notifyListeners();
  }

  void addConfiguration() {
    final names = _configurations.map((c) => c.name).toSet();
    var idx = _configurations.length + 1;
    while (names.contains(defaultName(idx))) {
      idx += 1;
    }

    final usedPorts = _configurations
        .expand((c) => c.connection.forwardRules)
        .map((r) => int.tryParse(r.localPort))
        .whereType<int>()
        .toSet();
    var port = 5901;
    while (usedPorts.contains(port)) {
      port += 1;
    }

    final cfg = SSHConfiguration(
      name: defaultName(idx),
      defaultLocalPort: '$port',
    );
    _configurations.add(cfg);
    selectedId = cfg.id;
    _changed();
  }

  /// Same semantics as [ReorderableList.onReorder].
  void move(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final cfg = _configurations.removeAt(oldIndex);
    _configurations.insert(newIndex, cfg);
    _changed();
  }

  void removeSelected() {
    final id = selectedId;
    if (id != null) remove(id);
  }

  /// Removes a configuration, stopping its tunnel. The selection only moves
  /// if the removed configuration was the selected one.
  void remove(String id) {
    final index = _configurations.indexWhere((c) => c.id == id);
    if (index < 0) return;
    final removed = _configurations.removeAt(index);
    unawaited(removed.connection.stop());
    if (selectedId == id) {
      selectedId = _configurations.isEmpty
          ? null
          : _configurations[min(index, _configurations.length - 1)].id;
    }
    _changed();
  }

  /// Stops every running tunnel and waits for them (used when quitting).
  Future<void> stopAll() async {
    await Future.wait(
      runningConfigurations.map((c) => c.connection.stopAndWait()),
    );
  }

  /// Writes pending changes immediately (used when quitting).
  Future<void> saveNow() async {
    _saveTimer?.cancel();
    await _save();
  }

  Future<void> _loadSettings() async {
    final file = _settingsFile;
    if (file == null || !await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final raw = decoded['quitBehavior'];
        _quitBehavior = QuitBehavior.values.firstWhere(
          (b) => b.name == raw,
          orElse: () => QuitBehavior.ask,
        );
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    final file = _settingsFile;
    if (file == null) return;
    try {
      await file.writeAsString(
        jsonEncode({'quitBehavior': _quitBehavior.name}),
        flush: true,
      );
    } catch (e) {
      debugPrint('SSH Túnel: failed to save settings: $e');
    }
  }

  void _changed() {
    _attachObservers();
    _scheduleSave();
    notifyListeners();
  }

  void _attachObservers() {
    for (final detach in _detachers) {
      detach();
    }
    _detachers.clear();

    for (final cfg in _configurations) {
      void onChange() {
        _scheduleSave();
        notifyListeners();
      }

      cfg.addListener(onChange);
      cfg.connection.addListener(onChange);
      _detachers.add(() {
        cfg.removeListener(onChange);
        cfg.connection.removeListener(onChange);
      });
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final file = _saveFile;
    if (file == null) return;

    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert(
      _configurations.map((c) => c.toJson()).toList(),
    );
    // Status/log changes also notify; skip the write if nothing persisted changed.
    if (json == _lastSavedJson) return;

    try {
      // Write atomically so a crash mid-write cannot corrupt the configs.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
      _lastSavedJson = json;
    } catch (e) {
      debugPrint('SSH Túnel: failed to save configurations: $e');
    }
  }

  static Future<void> _backupUnreadable(File file) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    try {
      await file.copy('${file.path}.recovery-$stamp.json');
    } catch (_) {}
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

    return Directory('${Directory.current.path}/.ssh_tunnelapp');
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _wakeDetector?.stop();
    for (final detach in _detachers) {
      detach();
    }
    for (final cfg in _configurations) {
      cfg.connection.dispose();
      cfg.dispose();
    }
    super.dispose();
  }
}

/// Detects that the computer was asleep, without any platform plugin.
///
/// A periodic timer compares wall-clock time with the monotonic clock: the
/// monotonic clock does not advance while the system sleeps (macOS, Linux),
/// so a large difference means the machine just woke up. A very large wall
/// gap is also treated as a wake, for platforms whose monotonic clock keeps
/// counting during sleep.
class WakeDetector {
  WakeDetector({required this.onWake});

  final VoidCallback onWake;
  static const _interval = Duration(seconds: 5);

  Timer? _timer;
  final Stopwatch _mono = Stopwatch();
  DateTime _lastWall = DateTime.now();
  Duration _lastMono = Duration.zero;

  void start() {
    _mono.start();
    _lastWall = DateTime.now();
    _lastMono = _mono.elapsed;
    _timer = Timer.periodic(_interval, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final wall = DateTime.now();
    final mono = _mono.elapsed;
    final wallDelta = wall.difference(_lastWall);
    final monoDelta = mono - _lastMono;
    _lastWall = wall;
    _lastMono = mono;

    final slept =
        wallDelta - monoDelta > const Duration(seconds: 15) ||
        wallDelta > const Duration(seconds: 90);
    if (slept) onWake();
  }
}

class SSHConfiguration extends ChangeNotifier {
  SSHConfiguration({required this.name, required String defaultLocalPort})
    : id = nextId(),
      connection = SSHConnectionController(defaultLocalPort: defaultLocalPort);

  SSHConfiguration._({
    required this.id,
    required this.name,
    required this.connection,
  });

  factory SSHConfiguration.fromJson(Map<String, dynamic> json) {
    final connectionJson = json['connection'];
    final connection = connectionJson is Map
        ? SSHConnectionController.fromSnapshot(
            Map<String, dynamic>.from(connectionJson),
          )
        : SSHConnectionController(defaultLocalPort: '5901');

    return SSHConfiguration._(
      id: coerceUuidString(json['id']),
      name: (json['name'] as String?) ?? l10n.fallbackConfigName,
      connection: connection,
    );
  }

  final String id;
  String name;
  final SSHConnectionController connection;

  void setName(String value) {
    if (name == value) return;
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
      id: nextId(),
      name: name,
      localPort: localPort,
      remoteHost: 'localhost',
      remotePort: '5900',
    );
  }

  factory PortForwardRule.fromJson(Map<String, dynamic> json) {
    return PortForwardRule(
      id: coerceUuidString(json['id']),
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

// MARK: - UUID helpers

final Random _idRandom = Random.secure();

String nextId() {
  final bytes = List<int>.generate(16, (_) => _idRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isUuidString(dynamic raw) => raw is String && _uuidPattern.hasMatch(raw);

String coerceUuidString(dynamic raw) {
  if (_isUuidString(raw)) return (raw as String).toLowerCase();
  return nextId();
}

bool _configurationNeedsMigration(Map<String, dynamic> json) {
  if (!_isUuidString(json['id'])) return true;

  final connection = json['connection'];
  if (connection is! Map) return true;

  final rules = connection['forwardRules'];
  if (rules is! List || rules.isEmpty) return true;

  for (final rule in rules) {
    if (rule is! Map || !_isUuidString(rule['id'])) return true;
  }
  return false;
}

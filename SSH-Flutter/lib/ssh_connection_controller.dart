import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';

import 'process_runner.dart';
import 'ssh_config_store.dart';

enum TunnelPhaseKind { stopped, connecting, retrying, active, stopping, error }

class TunnelPhase {
  const TunnelPhase._(this.kind, [this.message = '', this.seconds = 0]);

  const TunnelPhase.stopped() : this._(TunnelPhaseKind.stopped);
  const TunnelPhase.connecting() : this._(TunnelPhaseKind.connecting);
  const TunnelPhase.retrying(int seconds)
    : this._(TunnelPhaseKind.retrying, '', seconds);
  const TunnelPhase.active() : this._(TunnelPhaseKind.active);
  const TunnelPhase.stopping() : this._(TunnelPhaseKind.stopping);
  const TunnelPhase.error(String message)
    : this._(TunnelPhaseKind.error, message);

  final TunnelPhaseKind kind;
  final String message;
  final int seconds;
}

enum DetectedStateType {
  activeOursControlMaster,
  activeMatchesConfigByPid,
  portUsedByOther,
  stopped,
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

  bool get isActive =>
      type == DetectedStateType.activeOursControlMaster ||
      type == DetectedStateType.activeMatchesConfigByPid;
}

enum FailureKind { hostKeyChanged, addressInUse, authOrKey, config, transient, other }

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

  TunnelPhase _phase = const TunnelPhase.stopped();
  TunnelPhase get phase => _phase;

  String host = '';
  String user = '';
  String sshPort = '';
  String keyPath = '';
  List<PortForwardRule> forwardRules;

  bool autoReconnect = false;
  String logText = '';

  static const int _maxLogCharacters = 40000;

  static final String _sshPath = platformCommand(
    'ssh',
    macOSPath: '/usr/bin/ssh',
    linuxPaths: const ['/usr/bin/ssh', '/bin/ssh'],
    windowsPaths: const [r'C:\Windows\System32\OpenSSH\ssh.exe'],
  );
  static final String _lsofPath = platformCommand(
    'lsof',
    macOSPath: '/usr/sbin/lsof',
    linuxPaths: const ['/usr/bin/lsof', '/bin/lsof', '/usr/sbin/lsof'],
  );
  static final String _ssPath = platformCommand(
    'ss',
    macOSPath: 'ss',
    linuxPaths: const ['/usr/bin/ss', '/bin/ss', '/usr/sbin/ss'],
  );
  static final String _psPath = platformCommand(
    'ps',
    macOSPath: '/bin/ps',
    linuxPaths: const ['/usr/bin/ps', '/bin/ps'],
  );
  static final String _killPath = platformCommand(
    'kill',
    macOSPath: '/bin/kill',
    linuxPaths: const ['/usr/bin/kill', '/bin/kill'],
  );
  static final String _netstatPath = platformCommand(
    'netstat',
    macOSPath: '/usr/sbin/netstat',
    linuxPaths: const ['/usr/bin/netstat', '/bin/netstat'],
    windowsPaths: const [r'C:\Windows\System32\netstat.exe'],
  );
  static final String _taskkillPath = platformCommand(
    'taskkill',
    macOSPath: 'taskkill',
    windowsPaths: const [r'C:\Windows\System32\taskkill.exe'],
  );
  static final String _tasklistPath = platformCommand(
    'tasklist',
    macOSPath: 'tasklist',
    windowsPaths: const [r'C:\Windows\System32\tasklist.exe'],
  );
  static final String _powershellPath = platformCommand(
    'powershell',
    macOSPath: 'powershell',
    windowsPaths: const [
      r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
    ],
  );

  Process? _process;
  Timer? _statusTimer;
  Timer? _reconnectTimer;
  bool _isProbing = false;
  int _failures = 0;
  int? _externalMatchingPid;

  /// Output of the current ssh attempt only, used to classify failures.
  final StringBuffer _attemptLog = StringBuffer();

  /// Bumped on every user start/stop so stale async results are discarded.
  int _generation = 0;
  bool _disposed = false;

  // MARK: - Public state

  /// True while a tunnel is up or being set up/torn down (fields are locked).
  bool get isRunning =>
      _phase.kind != TunnelPhaseKind.stopped &&
      _phase.kind != TunnelPhaseKind.error;

  bool get isStopping => _phase.kind == TunnelPhaseKind.stopping;

  String get statusLabel {
    switch (_phase.kind) {
      case TunnelPhaseKind.active:
        return 'Actiu';
      case TunnelPhaseKind.connecting:
      case TunnelPhaseKind.retrying:
        return 'Connectant';
      case TunnelPhaseKind.stopping:
        return 'Aturant';
      case TunnelPhaseKind.stopped:
        return 'Aturat';
      case TunnelPhaseKind.error:
        return 'Error';
    }
  }

  String get statusDetail {
    switch (_phase.kind) {
      case TunnelPhaseKind.active:
        return 'localhost:${_localPortsSummary()}';
      case TunnelPhaseKind.connecting:
        return 'Connectant…';
      case TunnelPhaseKind.retrying:
        return 'Reintentant en ${_phase.seconds}s…';
      case TunnelPhaseKind.stopping:
        return 'Aturant…';
      case TunnelPhaseKind.stopped:
        return '';
      case TunnelPhaseKind.error:
        return _phase.message;
    }
  }

  Color get statusColor {
    switch (_phase.kind) {
      case TunnelPhaseKind.active:
        return CupertinoColors.systemGreen;
      case TunnelPhaseKind.connecting:
      case TunnelPhaseKind.retrying:
      case TunnelPhaseKind.stopping:
        return CupertinoColors.systemOrange;
      case TunnelPhaseKind.stopped:
        return CupertinoColors.systemGrey;
      case TunnelPhaseKind.error:
        return CupertinoColors.systemRed;
    }
  }

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

  // MARK: - Field setters

  void setHost(String value) => _set(host != value, () => host = value);
  void setUser(String value) => _set(user != value, () => user = value);
  void setSshPort(String value) =>
      _set(sshPort != value, () => sshPort = value);

  void setKeyPath(String value) {
    final normalized = _normalizeKeyPath(value);
    _set(keyPath != normalized, () => keyPath = normalized);
  }

  void setAutoReconnect(bool value) =>
      _set(autoReconnect != value, () => autoReconnect = value);

  void updateRuleName(String id, String value) =>
      _updateRule(id, (r) => r.name != value, (r) => r.name = value);
  void updateRuleLocalPort(String id, String value) =>
      _updateRule(id, (r) => r.localPort != value, (r) => r.localPort = value);
  void updateRuleRemoteHost(String id, String value) => _updateRule(
    id,
    (r) => r.remoteHost != value,
    (r) => r.remoteHost = value,
  );
  void updateRuleRemotePort(String id, String value) => _updateRule(
    id,
    (r) => r.remotePort != value,
    (r) => r.remotePort = value,
  );

  void _set(bool changed, VoidCallback apply) {
    if (!changed) return;
    apply();
    _notify();
  }

  void _updateRule(
    String id,
    bool Function(PortForwardRule) changed,
    void Function(PortForwardRule) apply,
  ) {
    final idx = forwardRules.indexWhere((r) => r.id == id);
    if (idx < 0 || !changed(forwardRules[idx])) return;
    apply(forwardRules[idx]);
    _notify();
  }

  void clearLog() {
    logText = '';
    _notify();
  }

  void addForwardRule() {
    if (isRunning) return;
    forwardRules.add(
      PortForwardRule(
        id: nextId(),
        name: _suggestedRuleName(),
        localPort: _suggestedLocalPort(),
        remoteHost: 'localhost',
        remotePort: '5900',
      ),
    );
    _notify();
  }

  void removeForwardRule(String id) {
    if (isRunning || forwardRules.length == 1) return;
    forwardRules = forwardRules.where((rule) => rule.id != id).toList();
    _notify();
  }

  // MARK: - User actions

  void start({bool clearLog = true}) {
    if (isRunning) return;
    _generation += 1;
    _failures = 0;
    _externalMatchingPid = null;
    if (clearLog) logText = '';
    unawaited(_connect());
  }

  Future<void> stop() => _performStop();

  /// Re-inspects the system (on launch, or to adopt a tunnel started outside the app).
  Future<void> refresh() async {
    if (_isProbing ||
        _process != null ||
        _reconnectTimer != null ||
        _phase.kind == TunnelPhaseKind.stopping ||
        !_hasTarget) {
      return;
    }
    final gen = _generation;
    _isProbing = true;
    final DetectedState state;
    try {
      state = await _detectCurrentState();
    } finally {
      _isProbing = false;
    }
    if (gen != _generation || _disposed) return;

    if (state.type == DetectedStateType.stopped &&
        _phase.kind != TunnelPhaseKind.active) {
      _setPhase(const TunnelPhase.stopped());
    } else {
      _apply(state);
    }
  }

  /// Called after the computer wakes from sleep.
  void systemDidWake() {
    if (!isRunning || isStopping) return;

    _stopTimer();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (autoReconnect) {
      // The TCP connection almost certainly died during sleep, but the ssh
      // master may not notice for ~30s. Restart it right away instead.
      _appendLog('[info] Wake from sleep: restarting tunnel');
      unawaited(() async {
        await _performStop();
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!_disposed) start(clearLog: false);
      }());
    } else if (_phase.kind == TunnelPhaseKind.active || _process != null) {
      _startTimer();
      unawaited(_tick());
    } else {
      _setPhase(const TunnelPhase.stopped());
    }
  }

  // MARK: - Connect / stop

  bool get _supportsControlMaster => !Platform.isWindows;

  bool get _hasTarget => host.trim().isNotEmpty && user.trim().isNotEmpty;

  Future<void> _connect() async {
    if (_process != null) return;

    final problem = _validationError();
    if (problem != null) {
      _appendLog('[error] $problem');
      _setPhase(TunnelPhase.error(problem));
      return;
    }

    _setPhase(const TunnelPhase.connecting());
    final gen = _generation;
    final state = await _detectCurrentState();
    if (gen != _generation ||
        _disposed ||
        _phase.kind != TunnelPhaseKind.connecting) {
      return;
    }

    if (state.type == DetectedStateType.stopped) {
      await _launchSsh(gen);
    } else {
      if (state.type == DetectedStateType.portUsedByOther) {
        _appendLog('[error] Local port in use by another process.');
      }
      _apply(state);
    }
  }

  Future<void> _launchSsh(int gen) async {
    final args = <String>['-N', '-T'];
    final key = _expandHome(keyPath.trim());
    if (key.isNotEmpty) args.addAll(['-i', key]);
    final port = sshPort.trim();
    if (port.isNotEmpty) args.addAll(['-p', port]);
    for (final f in _forwardSpecs) {
      args.addAll(['-L', f]);
    }

    args.addAll([
      '-o', 'ExitOnForwardFailure=yes',
      '-o', 'ServerAliveInterval=10',
      '-o', 'ServerAliveCountMax=3',
      // Generous: some servers (e.g. FreeBSD with tcp_wrappers + slow reverse
      // lookups) take several seconds just to send the SSH banner.
      '-o', 'ConnectTimeout=30',
      '-o', 'ConnectionAttempts=1',
      '-o', 'BatchMode=yes',
      '-o', 'StrictHostKeyChecking=accept-new',
    ]);

    if (Platform.isWindows) {
      args.addAll(['-o', 'UpdateHostKeys=no']);
    }

    if (_supportsControlMaster) {
      args.addAll([
        '-o', 'ControlMaster=yes',
        '-o', 'ControlPersist=yes',
        '-o', 'ControlPath=$_controlSocketPath',
      ]);
    }

    args.add(_sshTarget);

    _attemptLog.clear();
    Process p;
    try {
      p = await Process.start(_sshPath, args);
    } catch (e) {
      _appendLog('[error] Cannot execute ssh: $e');
      _setPhase(const TunnelPhase.error('no puc executar ssh'));
      return;
    }

    if (gen != _generation || _disposed) {
      p.kill(ProcessSignal.sigterm);
      return;
    }

    _process = p;
    unawaited(p.stdin.close().catchError((_) {}));
    final outDone = p.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((t) => _appendLog(t, attempt: true))
        .asFuture<void>()
        .catchError((_) {});
    final errDone = p.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((t) => _appendLog(t, attempt: true))
        .asFuture<void>()
        .catchError((_) {});
    _startTimer();

    unawaited(
      p.exitCode.then((code) async {
        // Let in-flight log chunks land before classifying the failure.
        await Future.wait([outDone, errDone]).timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => const [],
        );
        await _handleTermination(p, code, gen);
      }),
    );
  }

  Future<void> _handleTermination(Process p, int exitCode, int gen) async {
    if (_process != p) return;
    _process = null;
    if (gen != _generation || _disposed) return;

    // With ControlPersist the foreground ssh may exit while the master keeps running.
    final state = await _detectCurrentState();
    if (gen != _generation || _disposed || isStopping) return;
    if (state.type != DetectedStateType.stopped) {
      _apply(state);
      return;
    }

    _stopTimer();
    switch (_classifyFailure(_attemptLog.toString())) {
      case FailureKind.hostKeyChanged:
        _setPhase(
          const TunnelPhase.error(
            'la clau del host ha canviat (revisa ~/.ssh/known_hosts)',
          ),
        );
      case FailureKind.addressInUse:
        _setPhase(TunnelPhase.error('port local ocupat (${_localPortsSummary()})'));
      case FailureKind.authOrKey:
        _setPhase(const TunnelPhase.error('autenticació/clau'));
      case FailureKind.config:
        _setPhase(const TunnelPhase.error('configuració ssh'));
      case FailureKind.transient:
      case FailureKind.other:
        if (autoReconnect) {
          _scheduleReconnect();
        } else {
          _setPhase(TunnelPhase.error('ssh ha sortit (codi $exitCode)'));
        }
    }
  }

  Future<void> _performStop() async {
    if (isStopping) return;
    _generation += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopTimer();
    _setPhase(const TunnelPhase.stopping());

    final pid = _externalMatchingPid;
    _externalMatchingPid = null;
    final proc = _process;
    _process = null;

    final exited = _hasTarget && await _sshControlExit();
    if (!exited && pid != null) {
      if (!await _killPid(pid)) {
        _appendLog('[error] Could not stop ssh process $pid');
      }
    }
    proc?.kill(ProcessSignal.sigterm);

    if (!_disposed) _setPhase(const TunnelPhase.stopped());
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _failures += 1;
    final delay = min(pow(2, _failures).toInt(), 60);
    _setPhase(TunnelPhase.retrying(delay));

    final gen = _generation;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      if (gen != _generation || _disposed) return;
      unawaited(_connect());
    });
  }

  // MARK: - State application

  void _apply(DetectedState state) {
    switch (state.type) {
      case DetectedStateType.activeOursControlMaster:
        _externalMatchingPid = null;
        _becameActive();
      case DetectedStateType.activeMatchesConfigByPid:
        _externalMatchingPid = state.pid;
        _becameActive();
      case DetectedStateType.portUsedByOther:
        _externalMatchingPid = null;
        _stopTimer();
        _setPhase(TunnelPhase.error('port local ocupat (${_localPortsSummary()})'));
      case DetectedStateType.stopped:
        _externalMatchingPid = null;
        _stopTimer();
        if (_phase.kind == TunnelPhaseKind.active) {
          _appendLog('[info] Connection lost');
          if (autoReconnect) {
            _scheduleReconnect();
          } else {
            _setPhase(const TunnelPhase.error('connexió perduda'));
          }
        } else {
          _setPhase(const TunnelPhase.stopped());
        }
    }
  }

  void _becameActive() {
    _failures = 0;
    _setPhase(const TunnelPhase.active());
    _startTimer();
  }

  void _setPhase(TunnelPhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // MARK: - Polling

  void _startTimer() {
    if (_statusTimer != null) return;
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tick());
    });
  }

  void _stopTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  Future<void> _tick() async {
    final kind = _phase.kind;
    if (_isProbing ||
        (kind != TunnelPhaseKind.active && kind != TunnelPhaseKind.connecting)) {
      return;
    }
    final gen = _generation;
    _isProbing = true;
    final DetectedState state;
    try {
      state = await _detectCurrentState();
    } finally {
      _isProbing = false;
    }
    if (gen != _generation || _disposed) return;

    switch (_phase.kind) {
      case TunnelPhaseKind.connecting:
        // Only promote to active; failures are reported by the termination handler.
        if (state.isActive) _apply(state);
      case TunnelPhaseKind.active:
        // If our foreground ssh is still alive, let its exit handler decide.
        if (state.type == DetectedStateType.stopped && _process != null) return;
        _apply(state);
      default:
        break;
    }
  }

  // MARK: - Detection

  Future<DetectedState> _detectCurrentState() async {
    if (!_hasTarget) return const DetectedState.stopped();

    if (await _isOurTunnelActive()) {
      return const DetectedState.activeOursControlMaster();
    }

    for (final rule in forwardRules) {
      final lp = int.tryParse(rule.localPort.trim());
      if (lp == null || lp < 1 || lp > 65535) continue;

      final pid = await _listeningPid(lp);
      if (pid == null) {
        if (await _isPortListening(lp)) {
          return const DetectedState.portUsedByOther();
        }
        continue;
      }

      final cmd = await _commandLine(pid);
      return _matchesOurTunnelCommandLine(cmd)
          ? DetectedState.activeMatchesConfigByPid(pid)
          : const DetectedState.portUsedByOther();
    }

    return const DetectedState.stopped();
  }

  Future<bool> _isOurTunnelActive() async {
    if (!_supportsControlMaster) return false;
    final res = await runCommand(_sshPath, [
      '-o', 'BatchMode=yes',
      '-S', _controlSocketPath,
      '-O', 'check',
      _sshTarget,
    ]);
    return res.exitCode == 0;
  }

  Future<bool> _sshControlExit() async {
    if (!_supportsControlMaster) return false;
    final res = await runCommand(_sshPath, [
      '-o', 'BatchMode=yes',
      '-S', _controlSocketPath,
      '-O', 'exit',
      _sshTarget,
    ]);
    return res.exitCode == 0;
  }

  Future<int?> _listeningPid(int port) async {
    if (Platform.isWindows) return _windowsListeningPid(port);

    // -b: avoid kernel calls that can block (stat on dead network mounts).
    // -w: suppress the warnings -b produces.
    final res = await runCommand(_lsofPath, [
      '-nP', '-b', '-w',
      '-iTCP:$port',
      '-sTCP:LISTEN',
      '-Fp',
    ]);
    if (res.exitCode != 0) return null;

    for (final line in res.stdout.split('\n')) {
      if (line.startsWith('p')) {
        final pid = int.tryParse(line.substring(1));
        if (pid != null) return pid;
      }
    }
    return null;
  }

  Future<int?> _windowsListeningPid(int port) async {
    final res = await runCommand(_netstatPath, ['-ano', '-p', 'tcp']);
    if (res.exitCode != 0 || res.stdout.trim().isEmpty) return null;

    for (final rawLine in res.stdout.split('\n')) {
      final cols = rawLine.trim().split(RegExp(r'\s+'));
      if (cols.length < 5) continue;

      final proto = cols[0].toUpperCase();
      final state = cols[3].toUpperCase();
      final pid = int.tryParse(cols[4]);
      if (proto != 'TCP' || state != 'LISTENING' || pid == null) continue;
      if (_endpointHasPort(cols[1], port)) return pid;
    }
    return null;
  }

  Future<String> _commandLine(int pid) async {
    if (Platform.isWindows) {
      final script =
          '(Get-CimInstance Win32_Process -Filter "ProcessId = $pid").CommandLine';
      final fromPowerShell = await runCommand(_powershellPath, [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ], timeout: const Duration(seconds: 10));
      if (fromPowerShell.exitCode == 0) {
        final commandLine = fromPowerShell.stdout.trim();
        if (commandLine.isNotEmpty) return commandLine;
      }

      final fromTasklist = await runCommand(_tasklistPath, [
        '/FI', 'PID eq $pid',
        '/FO', 'CSV',
        '/NH',
      ]);
      if (fromTasklist.exitCode == 0) {
        final out = fromTasklist.stdout.trim();
        final line = out.isEmpty ? '' : out.split('\n').first;
        if (line.isNotEmpty && !line.contains('No tasks are running')) {
          return line;
        }
      }
      return '';
    }

    final res = await runCommand(
      _psPath,
      ['-p', '$pid', '-o', 'command='],
      timeout: const Duration(seconds: 3),
    );
    return res.stdout.trim();
  }

  /// Token-based match so that e.g. `-p 22` does not match `-p 2222`.
  bool _matchesOurTunnelCommandLine(String cmd) {
    final lower = cmd.toLowerCase();
    if (Platform.isWindows) {
      if (!lower.contains('ssh.exe') && !lower.contains('\\ssh')) return false;
    } else if (!lower.contains('ssh')) {
      return false;
    }

    final tokens = cmd
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll('"', ''))
        .where((t) => t.isNotEmpty)
        .toList();
    if (!tokens.contains(_sshTarget)) return false;

    bool hasPair(String flag, String value) {
      if (tokens.contains('$flag$value')) return true;
      for (var i = 0; i + 1 < tokens.length; i++) {
        if (tokens[i] == flag && tokens[i + 1] == value) return true;
      }
      return false;
    }

    final port = sshPort.trim().isEmpty ? '22' : sshPort.trim();
    if (port != '22' || tokens.contains('-p')) {
      if (!hasPair('-p', port)) return false;
    }
    for (final fwd in _forwardSpecs) {
      if (!hasPair('-L', fwd)) return false;
    }
    return true;
  }

  Future<bool> _killPid(int pid) async {
    if (Platform.isWindows) {
      final res = await runCommand(_taskkillPath, ['/PID', '$pid', '/T', '/F']);
      return res.exitCode == 0;
    }

    try {
      if (Process.killPid(pid, ProcessSignal.sigterm)) return true;
    } catch (_) {
      // Fall back to the external command.
    }
    final res = await runCommand(_killPath, ['-TERM', '$pid']);
    return res.exitCode == 0;
  }

  Future<bool> _isPortListening(int port) async {
    if (Platform.isLinux) {
      final res = await runCommand(_ssPath, ['-lntH']);
      if (res.exitCode != 0 || res.stdout.trim().isEmpty) return false;

      for (final line in res.stdout.split('\n')) {
        final cols = line.trim().split(RegExp(r'\s+'));
        if (cols.length < 2) continue;
        if (_endpointHasPort(cols[cols.length - 2], port)) return true;
      }
      return false;
    }

    if (Platform.isWindows) {
      return await _windowsListeningPid(port) != null;
    }

    return false;
  }

  bool _endpointHasPort(String endpoint, int port) {
    return endpoint.endsWith(':$port') || endpoint.endsWith(']:$port');
  }

  // MARK: - Helpers

  String? _validationError() {
    if (host.trim().isEmpty) return "cal indicar el host";
    if (user.trim().isEmpty) return "cal indicar l'usuari";
    final port = sshPort.trim();
    if (port.isNotEmpty && !_isValidPort(port)) return 'port SSH invàlid';
    if (forwardRules.isEmpty) return 'cap regla de port definida';
    final seen = <int>{};
    for (final r in forwardRules) {
      if (!_isValidPort(r.localPort.trim()) ||
          !_isValidPort(r.remotePort.trim())) {
        return 'ports invàlids a ${r.name}';
      }
      if (r.remoteHost.trim().isEmpty) return 'falta el host remot a ${r.name}';
      final lp = int.parse(r.localPort.trim());
      if (!seen.add(lp)) return 'port local $lp repetit';
    }
    return null;
  }

  static bool _isValidPort(String s) {
    final v = int.tryParse(s);
    return v != null && v >= 1 && v <= 65535;
  }

  String _expandHome(String path) {
    if (Platform.isWindows) return path;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return path;
    if (path == '~') return home;
    if (path.startsWith('~/')) return '$home/${path.substring(2)}';
    return path;
  }

  void _appendLog(String raw, {bool attempt = false}) {
    final lines = raw
        .replaceAll('\r', '')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    final text = lines.join('\n');
    if (attempt) _attemptLog.writeln(text);
    logText = logText.isEmpty ? text : '$logText\n$text';
    if (logText.length > _maxLogCharacters) {
      logText = logText.substring(logText.length - _maxLogCharacters ~/ 2);
    }
    _notify();
  }

  String _localPortsSummary() =>
      forwardRules.map((r) => r.localPort).join(',');

  List<String> get _forwardSpecs => forwardRules
      .map(
        (r) =>
            '${r.localPort.trim()}:${r.remoteHost.trim()}:${r.remotePort.trim()}',
      )
      .toList();

  String _suggestedLocalPort() {
    final used = forwardRules
        .map((r) => int.tryParse(r.localPort))
        .whereType<int>()
        .toSet();
    var port = 5901;
    while (used.contains(port)) {
      port += 1;
    }
    return '$port';
  }

  String _suggestedRuleName() {
    final used = forwardRules.map((r) => r.name.trim()).toSet();
    var idx = 1;
    while (used.contains('Regla $idx')) {
      idx += 1;
    }
    return 'Regla $idx';
  }

  String get _sshTarget => '${user.trim()}@${host.trim()}';

  /// NOTE: keep this format stable so tunnels started by previous versions
  /// (and by the native macOS app) are still recognised.
  String get _controlSocketPath {
    final rulesKey =
        forwardRules
            .map((r) => 'L${r.localPort}->${r.remoteHost}:${r.remotePort}')
            .toList()
          ..sort();

    final base = '$user@$host:$sshPort|${rulesKey.join('|')}';
    return _socketPathForDigest(_stableShortHash(base));
  }

  String _socketPathForDigest(String digest) {
    final home = _homePath() ?? Directory.current.path;
    final sshDir = _joinPath(home, '.ssh');
    final fileName = Platform.isWindows
        ? 'tunnelctl_$digest.ctl'
        : 'tunnelctl_$digest.sock';
    return _joinPath(sshDir, fileName);
  }

  String? _homePath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return home;
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) return userProfile;
    return null;
  }

  String _joinPath(String base, String leaf) {
    if (base.endsWith('/') || base.endsWith(r'\')) return '$base$leaf';
    return '$base${Platform.pathSeparator}$leaf';
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

  FailureKind _classifyFailure(String text) {
    final s = text.toLowerCase();

    if (s.contains('host key verification failed') ||
        s.contains('remote host identification has changed')) {
      return FailureKind.hostKeyChanged;
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
        s.contains('unknown option') ||
        s.contains('bad port')) {
      return FailureKind.config;
    }
    if (s.contains('timed out') ||
        s.contains('connection reset by peer') ||
        s.contains('broken pipe') ||
        s.contains('connection refused') ||
        s.contains('network is unreachable') ||
        s.contains('no route to host') ||
        s.contains('could not resolve hostname') ||
        s.contains('server not responding')) {
      return FailureKind.transient;
    }
    return FailureKind.other;
  }

  @override
  void dispose() {
    _disposed = true;
    _statusTimer?.cancel();
    _reconnectTimer?.cancel();
    // Intentionally not killing the ssh process: with ControlPersist the tunnel
    // outlives the app and is re-adopted on next launch (as in the macOS app).
    super.dispose();
  }

  // MARK: - Snapshot parsing / key path normalisation

  static List<PortForwardRule> _parseRules(dynamic raw) {
    final parsed = <PortForwardRule>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          parsed.add(PortForwardRule.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    if (parsed.isEmpty) {
      return [PortForwardRule.createDefault('Regla 1', '5901')];
    }
    return parsed;
  }

  static String _normalizeKeyPath(String value) {
    if (Platform.isWindows) return _normalizeWindowsKeyPath(value);
    if (!(Platform.isMacOS || Platform.isLinux)) return value;
    if (value == r'$HOME') return '~';
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
    if (home == null || home.isEmpty) return value;

    const prefixes = [
      '~/',
      '~\\',
      r'%USERPROFILE%/',
      '%USERPROFILE%\\',
      r'%HOMEDRIVE%%HOMEPATH%/',
      '%HOMEDRIVE%%HOMEPATH%\\',
      r'$HOME/',
      '\$HOME\\',
    ];
    for (final prefix in prefixes) {
      if (_startsWithIgnoreCase(value, prefix)) {
        return _joinWindowsHome(home, value.substring(prefix.length));
      }
    }

    const exact = ['~', r'%USERPROFILE%', r'%HOMEDRIVE%%HOMEPATH%', r'$HOME'];
    for (final e in exact) {
      if (value.toLowerCase() == e.toLowerCase()) return home;
    }
    return value;
  }

  static String? _windowsHomePath() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) return userProfile;
    final drive = Platform.environment['HOMEDRIVE'];
    final path = Platform.environment['HOMEPATH'];
    if (drive != null && drive.isNotEmpty && path != null && path.isNotEmpty) {
      return '$drive$path';
    }
    return null;
  }

  static String _joinWindowsHome(String home, String suffix) {
    if (suffix.isEmpty) return home;
    final cleanSuffix = suffix.replaceAll('/', '\\');
    if (home.endsWith('\\') || home.endsWith('/')) return '$home$cleanSuffix';
    return '$home\\$cleanSuffix';
  }

  static bool _startsWithIgnoreCase(String value, String prefix) {
    if (value.length < prefix.length) return false;
    return value.substring(0, prefix.length).toLowerCase() ==
        prefix.toLowerCase();
  }
}

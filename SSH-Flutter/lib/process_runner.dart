// Helpers to run short-lived command-line tools (ssh -O, lsof, ps, netstat…).
//
// Every call has a timeout: after a sleep/wake cycle some of these tools can
// block for a long time (e.g. lsof on a dead network mount). Without a timeout
// the awaiting code never resumes and the tunnel state gets stuck.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
}

Future<CommandResult> runCommand(
  String exe,
  List<String> args, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  Process p;
  try {
    p = await Process.start(exe, args);
  } catch (e) {
    return CommandResult(exitCode: -1, stdout: '', stderr: '$e');
  }
  unawaited(p.stdin.close().catchError((_) {}));

  final out = StringBuffer();
  final err = StringBuffer();
  final outDone = p.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(out.write)
      .asFuture<void>()
      .catchError((_) {});
  final errDone = p.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(err.write)
      .asFuture<void>()
      .catchError((_) {});

  int code;
  try {
    code = await p.exitCode.timeout(timeout);
  } on TimeoutException {
    p.kill(ProcessSignal.sigterm);
    Timer(const Duration(seconds: 1), () => p.kill(ProcessSignal.sigkill));
    return CommandResult(
      exitCode: -2,
      stdout: '',
      stderr: 'timed out after ${timeout.inSeconds}s',
      timedOut: true,
    );
  }

  // A grandchild may still hold the pipes open; don't wait forever for EOF.
  await Future.wait([outDone, errDone]).timeout(
    const Duration(seconds: 1),
    onTimeout: () => const [],
  );
  return CommandResult(
    exitCode: code,
    stdout: out.toString(),
    stderr: err.toString(),
  );
}

/// Resolves the full path of a system tool for the current platform.
String platformCommand(
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
    // 1. Known fixed paths (locale-independent, e.g. System32\OpenSSH).
    for (final path in windowsPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // 2. %ProgramFiles% and %ProgramFiles(x86)% are locale-aware env vars
    //    (e.g. "Archivos de programa" on Spanish Windows).
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

    // 3. PATH-installed OpenSSH (Git for Windows, winget…).
    try {
      final result = Process.runSync(r'C:\Windows\System32\where.exe', [
        command,
      ]);
      if (result.exitCode == 0) {
        final first = result.stdout
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

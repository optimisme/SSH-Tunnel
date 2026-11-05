// Read-only helpers around the user's OpenSSH setup: host aliases declared in
// ~/.ssh/config, private keys in ~/.ssh and `ssh -G` resolution.

import 'dart:io';

import 'process_runner.dart';

class ResolvedSshHost {
  const ResolvedSshHost({
    required this.hostName,
    required this.user,
    required this.port,
    required this.identityFiles,
  });

  final String hostName;
  final String user;
  final String port;
  final List<String> identityFiles;

  String get summary {
    final p = port.isEmpty || port == '22' ? '' : ':$port';
    return '$user@$hostName$p';
  }

  @override
  bool operator ==(Object other) =>
      other is ResolvedSshHost &&
      other.hostName == hostName &&
      other.user == user &&
      other.port == port &&
      other.identityFiles.join('\n') == identityFiles.join('\n');

  @override
  int get hashCode =>
      Object.hash(hostName, user, port, identityFiles.join('\n'));
}

class ParsedSshConfig {
  const ParsedSshConfig(this.aliases, this.includes);
  final List<String> aliases;
  final List<String> includes;
}

class SshConfigFile {
  static String? get homePath {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return home;
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) return profile;
    return null;
  }

  static String get sshDirectory =>
      '${homePath ?? Directory.current.path}${Platform.pathSeparator}.ssh';

  // MARK: Host aliases

  /// Concrete `Host` aliases (no wildcards or negations), following `Include`.
  static List<String> hostAliases({String? configPath}) {
    final seenFiles = <String>{};
    final result = <String>[];
    _collect(
      configPath ?? '$sshDirectory${Platform.pathSeparator}config',
      0,
      seenFiles,
      result,
    );
    final unique = <String>{};
    return result.where(unique.add).toList();
  }

  static void _collect(
    String path,
    int depth,
    Set<String> seenFiles,
    List<String> into,
  ) {
    if (depth >= 8) return;
    final file = File(path);
    final String text;
    try {
      if (!seenFiles.add(file.absolute.path)) return;
      text = file.readAsStringSync();
    } catch (_) {
      return;
    }
    final parsed = parse(text);
    into.addAll(parsed.aliases);
    for (final pattern in parsed.includes) {
      for (final included in _expandInclude(pattern)) {
        _collect(included, depth + 1, seenFiles, into);
      }
    }
  }

  /// Parses one ssh_config file.
  static ParsedSshConfig parse(String text) {
    final aliases = <String>[];
    final includes = <String>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final (keyword, args) = _splitDirective(line);
      switch (keyword.toLowerCase()) {
        case 'host':
          aliases.addAll(args.where((a) => !a.contains(RegExp(r'[*?!]'))));
        case 'include':
          includes.addAll(args);
      }
    }
    return ParsedSshConfig(aliases, includes);
  }

  static (String, List<String>) _splitDirective(String line) {
    final sep = line.indexOf(RegExp(r'[ \t=]'));
    if (sep < 0) return (line, const []);
    final keyword = line.substring(0, sep);
    final rest = line.substring(sep + 1).replaceFirst(RegExp(r'^[ \t=]+'), '');

    final args = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    var hasToken = false;
    for (final ch in rest.split('')) {
      if (ch == '"') {
        inQuotes = !inQuotes;
        hasToken = true;
      } else if ((ch == ' ' || ch == '\t') && !inQuotes) {
        if (hasToken) args.add(current.toString());
        current.clear();
        hasToken = false;
      } else {
        current.write(ch);
        hasToken = true;
      }
    }
    if (hasToken) args.add(current.toString());
    return (keyword, args);
  }

  /// Relative Include paths are relative to ~/.ssh. Wildcards are supported
  /// in the last path component (the common `config.d/*` case).
  static List<String> _expandInclude(String pattern) {
    var path = expandHome(pattern);
    final sep = Platform.pathSeparator;
    if (!File(path).isAbsolute) path = '$sshDirectory$sep$path';
    if (!path.contains(RegExp(r'[*?\[]'))) return [path];

    final slash = path.lastIndexOf(sep);
    final dir = Directory(path.substring(0, slash));
    final glob = RegExp(
      '^${RegExp.escape(path.substring(slash + 1)).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
    );
    try {
      final names =
          dir
              .listSync()
              .whereType<File>()
              .map((f) => f.path.substring(f.path.lastIndexOf(sep) + 1))
              .where((n) => !n.startsWith('.') && glob.hasMatch(n))
              .toList()
            ..sort();
      return names.map((n) => '${dir.path}$sep$n').toList();
    } catch (_) {
      return const [];
    }
  }

  // MARK: Keys

  /// Private keys in [dir] (default ~/.ssh), displayed with a `~/` prefix.
  static List<String> privateKeys({String? dir}) {
    final directory = Directory(dir ?? sshDirectory);
    const ignored = {
      'config',
      'known_hosts',
      'known_hosts.old',
      'authorized_keys',
      'environment',
    };
    try {
      final files = directory.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return files
          .where((f) {
            final name = f.uri.pathSegments.last;
            return !name.startsWith('.') &&
                !name.endsWith('.pub') &&
                !name.startsWith('tunnelctl_') &&
                !ignored.contains(name) &&
                isPrivateKey(f);
          })
          .map((f) => abbreviatingHome(f.path))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static bool isPrivateKey(File file) {
    try {
      final raf = file.openSync();
      try {
        final head = String.fromCharCodes(raf.readSync(64));
        return head.startsWith('-----BEGIN') && head.contains('PRIVATE KEY');
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  static String abbreviatingHome(String path) {
    final home = homePath;
    if (home == null || Platform.isWindows) return path;
    if (path == home) return '~';
    if (path.startsWith('$home/')) return '~${path.substring(home.length)}';
    return path;
  }

  static String expandHome(String path) {
    final home = homePath;
    if (home == null) return path;
    if (path == '~') return home;
    if (path.startsWith('~/') || path.startsWith(r'~\')) {
      return '$home${Platform.pathSeparator}${path.substring(2)}';
    }
    return path;
  }

  // MARK: ssh -G

  /// Effective settings for [host] as ssh would use them (reads config only).
  static Future<ResolvedSshHost?> resolve(String sshPath, String host) async {
    final res = await runCommand(sshPath, [
      '-G',
      host,
    ], timeout: const Duration(seconds: 3));
    if (res.exitCode != 0) return null;
    return parseResolved(res.stdout);
  }

  static ResolvedSshHost? parseResolved(String output) {
    var hostName = '';
    var user = '';
    var port = '';
    final identityFiles = <String>[];
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final space = line.indexOf(' ');
      if (space <= 0) continue;
      final key = line.substring(0, space);
      final value = line.substring(space + 1).trim();
      switch (key) {
        case 'hostname':
          hostName = value;
        case 'user':
          user = value;
        case 'port':
          port = value;
        case 'identityfile':
          identityFiles.add(value);
      }
    }
    if (hostName.isEmpty) return null;
    return ResolvedSshHost(
      hostName: hostName,
      user: user,
      port: port,
      identityFiles: identityFiles,
    );
  }
}

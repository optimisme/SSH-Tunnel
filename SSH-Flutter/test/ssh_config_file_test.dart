import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_flutter/ssh_config_file.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sshcfg'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('parse keeps concrete aliases and includes', () {
    final parsed = SshConfigFile.parse('''
# comment
Host bsd linux
  HostName 192.168.1.195
Host *.example.com !bad web?
Host="quoted alias"
  Include conf.d/*
Match host foo
''');
    expect(parsed.aliases, ['bsd', 'linux', 'quoted alias']);
    expect(parsed.includes, ['conf.d/*']);
  });

  test('hostAliases follows Include and ignores loops and duplicates', () {
    final conf = Directory('${dir.path}/conf.d')..createSync();
    File('${conf.path}/a').writeAsStringSync('Host alpha\nHost bsd\n');
    File('${conf.path}/b').writeAsStringSync('Host beta\nInclude ${dir.path}/config\n');
    File('${dir.path}/config').writeAsStringSync(
      'Host bsd\nInclude ${conf.path}/*\n',
    );
    expect(
      SshConfigFile.hostAliases(configPath: '${dir.path}/config'),
      ['bsd', 'alpha', 'beta'],
    );
  });

  test('privateKeys lists only private key files', () {
    File('${dir.path}/id_ed25519').writeAsStringSync(
      '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n',
    );
    File('${dir.path}/id_ed25519.pub').writeAsStringSync('ssh-ed25519 AAAA');
    File('${dir.path}/id_rsa').writeAsStringSync(
      '-----BEGIN RSA PRIVATE KEY-----\nabc\n',
    );
    File('${dir.path}/config').writeAsStringSync('Host x\n');
    File('${dir.path}/known_hosts').writeAsStringSync('x');
    File('${dir.path}/tunnelctl_abc.sock').writeAsStringSync('x');
    final keys = SshConfigFile.privateKeys(dir: dir.path);
    expect(keys.map((k) => k.split('/').last), ['id_ed25519', 'id_rsa']);
  });

  test('parseResolved reads ssh -G output', () {
    final r = SshConfigFile.parseResolved('''
user albert
hostname 192.168.1.195
port 2222
identityfile ~/.ssh/id_rsa
identityfile ~/.ssh/id_ed25519
''');
    expect(r, isNotNull);
    expect(r!.hostName, '192.168.1.195');
    expect(r.user, 'albert');
    expect(r.port, '2222');
    expect(r.identityFiles, ['~/.ssh/id_rsa', '~/.ssh/id_ed25519']);
    expect(r.summary, 'albert@192.168.1.195:2222');
    expect(SshConfigFile.parseResolved('user x\n'), isNull);
  });

  test('home abbreviation round trip', () {
    final home = SshConfigFile.homePath!;
    expect(SshConfigFile.abbreviatingHome('$home/.ssh/id_rsa'), '~/.ssh/id_rsa');
    expect(SshConfigFile.expandHome('~/.ssh/id_rsa'), '$home/.ssh/id_rsa');
    expect(SshConfigFile.abbreviatingHome('/etc/ssh'), '/etc/ssh');
  });
}

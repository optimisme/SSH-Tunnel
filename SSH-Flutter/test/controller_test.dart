import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_flutter/ssh_connection_controller.dart';

void main() {
  group('classifyFailure', () {
    const cases = {
      'Host key verification failed.': FailureKind.hostKeyChanged,
      '@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @':
          FailureKind.hostKeyChanged,
      'bind [127.0.0.1]:5901: Address already in use':
          FailureKind.addressInUse,
      'channel_setup_fwd_listener_tcpip: cannot listen to port: 5901':
          FailureKind.addressInUse,
      'albert@host: Permission denied (publickey).': FailureKind.authOrKey,
      'Warning: Identity file /Users/a/.ssh/nope not accessible: No such file or directory.':
          FailureKind.authOrKey,
      'command-line line 0: Bad configuration option: foo':
          FailureKind.config,
      'Connection timed out during banner exchange': FailureKind.transient,
      'ssh: connect to host 192.168.1.195 port 22: No route to host':
          FailureKind.transient,
      'ssh: Could not resolve hostname nowhere: nodename nor servname provided':
          FailureKind.transient,
      'something unexpected': FailureKind.other,
    };
    cases.forEach((log, expected) {
      test(log, () {
        expect(SSHConnectionController.classifyFailure(log), expected);
      });
    });

    test('host key wins over permission denied', () {
      expect(
        SSHConnectionController.classifyFailure(
          'Host key verification failed.\nPermission denied',
        ),
        FailureKind.hostKeyChanged,
      );
    });
  });

  group('matchesCommandLine', () {
    bool matches(
      String cmd, {
      String target = 'albert@host',
      String port = '',
      List<String> forwards = const ['5901:localhost:5900'],
    }) => SSHConnectionController.matchesCommandLine(
      cmd,
      target: target,
      sshPort: port,
      forwards: forwards,
    );

    test('own command line', () {
      expect(
        matches(
          '/usr/bin/ssh -N -T -i /Users/a/.ssh/id_rsa -L 5901:localhost:5900 '
          '-o ExitOnForwardFailure=yes albert@host',
        ),
        isTrue,
      );
    });

    test('joined flag values', () {
      expect(
        matches('ssh -N -L5901:localhost:5900 -p2222 albert@host', port: '2222'),
        isTrue,
      );
    });

    test('port must match exactly', () {
      const cmd = '/usr/bin/ssh -N -p 2222 -L 5901:localhost:5900 albert@host';
      expect(matches(cmd, port: '22'), isFalse);
      expect(matches(cmd, port: '222'), isFalse);
      expect(matches(cmd, port: '2222'), isTrue);
    });

    test('rejects other targets, forwards and programs', () {
      expect(matches('/usr/bin/ssh -L 5901:localhost:5900 other@host'), isFalse);
      expect(matches('/usr/bin/ssh -L 5901:localhost:5999 albert@host'), isFalse);
      expect(
        matches('/usr/bin/autossh -L 5901:localhost:5900 albert@host'),
        isFalse,
      );
      expect(matches(''), isFalse);
    });

    test('bare alias target', () {
      expect(
        matches('/usr/bin/ssh -N -L 5901:localhost:5900 bsd', target: 'bsd'),
        isTrue,
      );
    });
  });

  group('controller', () {
    SSHConnectionController make() =>
        SSHConnectionController(defaultLocalPort: '5901');

    test('defaults', () {
      final c = make();
      expect(c.keyPath, SSHConnectionController.defaultKeyPath);
      expect(c.forwardRules.single.name, 'Rule 1');
      expect(c.forwardRules.single.localPort, '5901');
    });

    test('missing keyPath in a snapshot defaults to id_rsa, empty stays agent', () {
      expect(
        SSHConnectionController.fromSnapshot({'host': 'h'}).keyPath,
        SSHConnectionController.defaultKeyPath,
      );
      expect(
        SSHConnectionController.fromSnapshot({'host': 'h', 'keyPath': ''}).keyPath,
        '',
      );
    });

    test('control socket hash is stable across versions', () {
      final c = SSHConnectionController.fromSnapshot({
        'host': '192.168.1.196',
        'user': 'albert',
        'sshPort': '22',
        'forwardRules': [
          {
            'id': '00000000-0000-4000-8000-000000000001',
            'name': 'R',
            'localPort': '4229',
            'remoteHost': 'localhost',
            'remotePort': '22',
          },
        ],
      });
      expect(c.controlSocketPath, endsWith('tunnelctl_3b70b313b747b28a.sock'));
    });

    test('validation', () {
      final c = make();
      expect(c.validationError()?.kind, TunnelIssueKind.missingHost);
      c.setHost('bsd'); // no user: taken from ~/.ssh/config
      expect(c.validationError(), isNull);
      c.setSshPort('0');
      expect(c.validationError()?.kind, TunnelIssueKind.invalidSshPort);
      c.setSshPort('');
      c.addForwardRule();
      final second = c.forwardRules[1];
      c.updateRuleLocalPort(second.id, c.forwardRules[0].localPort);
      expect(
        c.validationError(),
        const TunnelIssue(TunnelIssueKind.duplicateLocalPort, '5901'),
      );
      c.updateRuleLocalPort(second.id, 'abc');
      expect(c.validationError()?.kind, TunnelIssueKind.invalidPorts);
      c.updateRuleLocalPort(second.id, '6000');
      c.updateRuleRemoteHost(second.id, ' ');
      expect(c.validationError()?.kind, TunnelIssueKind.missingRemoteHost);
    });

    test('issues have English messages', () {
      expect(
        const TunnelIssue(TunnelIssueKind.invalidPorts, 'Rule 2').message,
        'Invalid ports in “Rule 2”',
      );
    });

    test('moveForwardRule reorders and clamps', () {
      final c = make();
      c.addForwardRule();
      c.addForwardRule();
      final ids = c.forwardRules.map((r) => r.id).toList();
      c.moveForwardRule(0, 2);
      expect(c.forwardRules.map((r) => r.id), [ids[1], ids[2], ids[0]]);
      c.moveForwardRule(2, 99);
      expect(c.forwardRules.map((r) => r.id), [ids[1], ids[2], ids[0]]);
      c.moveForwardRule(2, -5);
      expect(c.forwardRules.map((r) => r.id), [ids[0], ids[1], ids[2]]);
      c.moveForwardRule(7, 0);
      expect(c.forwardRules.map((r) => r.id), ids);
    });

    test('snapshot round trip keeps rule order', () {
      final c = make()..setHost('h')..setUser('u');
      c.addForwardRule();
      c.moveForwardRule(1, 0);
      final copy = SSHConnectionController.fromSnapshot(c.snapshot());
      expect(copy.snapshot(), c.snapshot());
    });
  });
}

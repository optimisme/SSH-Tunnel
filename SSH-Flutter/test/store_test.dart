import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_flutter/ssh_config_store.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sshstore'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<SSHConfigStore> open() async {
    final store = SSHConfigStore(saveDirectory: dir, observeSystem: false);
    await store.initialize();
    return store;
  }

  test('add, move, save and reload', () async {
    final store = await open();
    store.addConfiguration();
    store.addConfiguration();
    store.addConfiguration();
    expect(store.configurations.map((c) => c.name), [
      'Connection 1',
      'Connection 2',
      'Connection 3',
    ]);
    // Each new configuration gets a free local port.
    expect(
      store.configurations.map((c) => c.connection.forwardRules.first.localPort),
      ['5901', '5902', '5903'],
    );
    store.move(2, 0);
    await store.saveNow();

    final reloaded = await open();
    expect(reloaded.configurations.map((c) => c.name), [
      'Connection 3',
      'Connection 1',
      'Connection 2',
    ]);
  });

  test('remove only moves the selection when the selected item goes', () async {
    final store = await open();
    store.addConfiguration();
    store.addConfiguration();
    store.addConfiguration();
    final ids = store.configurations.map((c) => c.id).toList();
    store.selectConfiguration(ids[2]);
    store.remove(ids[0]);
    expect(store.selectedId, ids[2]);
    store.remove(ids[2]);
    expect(store.selectedId, ids[1]);
    store.remove(ids[1]);
    expect(store.selectedId, isNull);
  });

  test('quit behavior persists', () async {
    final store = await open();
    expect(store.quitBehavior, QuitBehavior.ask);
    store.quitBehavior = QuitBehavior.keepTunnels;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final reloaded = await open();
    expect(reloaded.quitBehavior, QuitBehavior.keepTunnels);
  });

  test('unreadable configs are backed up, not overwritten', () async {
    File('${dir.path}/configs.json').writeAsStringSync('{not json');
    final store = await open();
    expect(store.configurations, isEmpty);
    final backups = dir
        .listSync()
        .where((e) => e.path.contains('recovery-'))
        .toList();
    expect(backups, hasLength(1));
  });

  test('old files without ids are migrated', () async {
    File('${dir.path}/configs.json').writeAsStringSync(
      jsonEncode([
        {
          'name': 'Old',
          'connection': {'host': 'h', 'forwardRules': []},
        },
      ]),
    );
    final store = await open();
    expect(store.configurations.single.name, 'Old');
    expect(store.runningConfigurations, isEmpty);
  });
}

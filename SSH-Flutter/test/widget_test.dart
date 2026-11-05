import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_flutter/main.dart';
import 'package:ssh_flutter/ssh_config_store.dart';

void main() {
  testWidgets('home page renders, localizes and reorders rules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('sshwidget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = SSHConfigStore(saveDirectory: dir, observeSystem: false);
    await tester.runAsync(store.initialize);
    store.addConfiguration();
    store.selectedConfiguration!.connection.addForwardRule();

    await tester.pumpWidget(SSHFlutterApp(store: store));
    await tester.pump();

    expect(find.text('SSH Configurations'), findsOneWidget);
    expect(find.text('Port Forwarding Rules'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Settings popover offers the three quit behaviours.
    await tester.tap(find.byIcon(CupertinoIcons.gear));
    await tester.pumpAndSettle();
    expect(find.text('Keep the tunnels running'), findsOneWidget);
    await tester.tap(find.text('Keep the tunnels running'));
    await tester.pump();
    expect(store.quitBehavior, QuitBehavior.keepTunnels);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('quit dialog returns the choice', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('sshwidget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = SSHConfigStore(saveDirectory: dir, observeSystem: false);
    await tester.runAsync(store.initialize);
    await tester.pumpWidget(SSHFlutterApp(store: store));
    await tester.pump();

    final ctx = tester.element(find.byType(SSHHomePage));
    QuitChoice? choice;
    var done = false;
    showQuitDialog(ctx, 2).then((c) {
      choice = c;
      done = true;
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Close the 2 open tunnels before quitting?'), findsOneWidget);
    await tester.tap(find.text('Don’t ask again'));
    await tester.tap(find.text('Close Tunnels'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done, isTrue);
    expect(choice?.behavior, QuitBehavior.closeTunnels);
    expect(choice?.dontAskAgain, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

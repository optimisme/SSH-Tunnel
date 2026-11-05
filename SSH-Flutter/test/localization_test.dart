import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_flutter/l10n.dart';

Map<String, dynamic> arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('every language has every message', () {
    final keys = arb('en').keys.where((k) => !k.startsWith('@')).toSet();
    for (final lang in ['ca', 'es']) {
      final other = arb(lang).keys.where((k) => !k.startsWith('@')).toSet();
      expect(other, keys, reason: lang);
    }
  });

  test('locale resolution', () {
    expect(resolveAppLocale(const [Locale('ca', 'ES')]).languageCode, 'ca');
    expect(resolveAppLocale(const [Locale('es', 'MX')]).languageCode, 'es');
    expect(resolveAppLocale(const [Locale('fr')]).languageCode, 'en');
  });

  test('translations and plurals', () {
    final ca = lookupAppLocalizations(const Locale('ca'));
    final es = lookupAppLocalizations(const Locale('es'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(ca.delete, 'Elimina');
    expect(es.delete, 'Eliminar');
    expect(ca.defaultRuleName(2), 'Regla 2');
    expect(en.quitTitle(1), isNot(contains('1')));
    expect(en.quitTitle(3), contains('3'));
    expect(ca.quitTitle(3), contains('3'));
  });

  test('updateL10n switches the global instance', () {
    updateL10n(const [Locale('ca')]);
    expect(l10n.defaultConfigName(1), 'Connexió 1');
    updateL10n(const [Locale('en')]);
    expect(l10n.defaultConfigName(1), 'Connection 1');
  });
}

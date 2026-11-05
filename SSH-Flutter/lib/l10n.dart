// Localized strings for code that has no BuildContext (controllers, logs).
//
// Widgets and controllers share the same instance, resolved from the system
// locales at startup and whenever they change.

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart'
    show BuildContext, Localizations, basicLocaleListResolution;

import 'l10n/app_localizations.dart';

export 'l10n/app_localizations.dart';

AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

/// Best supported match for [preferred]; English when none of them is supported
/// (the generated list starts with `ca`, which would otherwise be the fallback).
Locale resolveAppLocale(List<Locale> preferred) {
  final supported = AppLocalizations.supportedLocales;
  final anyMatch = preferred.any(
    (p) => supported.any((s) => s.languageCode == p.languageCode),
  );
  if (!anyMatch) return const Locale('en');
  return basicLocaleListResolution(preferred, supported);
}

/// Picks the best supported language for [preferred] (defaults to the system list).
Locale updateL10n([List<Locale>? preferred]) {
  final locale = resolveAppLocale(
    preferred ?? PlatformDispatcher.instance.locales,
  );
  l10n = lookupAppLocalizations(locale);
  return locale;
}

/// Localizations for [context]. Popovers and dialogs live in the root overlay,
/// above the app's localization scope, so they fall back to the global [l10n]
/// (kept in sync with the system languages by [updateL10n]).
AppLocalizations tr(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ?? l10n;

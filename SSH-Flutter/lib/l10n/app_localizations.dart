import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ca.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ca'),
    Locale('en'),
    Locale('es'),
  ];

  /// App name, not translated
  ///
  /// In en, this message translates to:
  /// **'SSH Túnel'**
  String get appTitle;

  /// Sidebar title
  ///
  /// In en, this message translates to:
  /// **'SSH Configurations'**
  String get sidebarTitle;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Add Configuration'**
  String get addConfiguration;

  /// Short button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Button tooltip
  ///
  /// In en, this message translates to:
  /// **'Delete Configuration'**
  String get deleteConfiguration;

  /// Confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String deleteConfirmTitle(String name);

  /// Confirmation message
  ///
  /// In en, this message translates to:
  /// **'If the tunnel is active, it will be stopped.'**
  String get deleteConfirmMessage;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Empty detail
  ///
  /// In en, this message translates to:
  /// **'Select a configuration or add a new one.'**
  String get noSelection;

  /// Section title
  ///
  /// In en, this message translates to:
  /// **'Configuration Name'**
  String get configurationName;

  /// Section title
  ///
  /// In en, this message translates to:
  /// **'SSH Connection'**
  String get sshConnection;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// Placeholder
  ///
  /// In en, this message translates to:
  /// **'Host name, IP or ~/.ssh/config alias'**
  String get hostPlaceholder;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// Placeholder; login name
  ///
  /// In en, this message translates to:
  /// **'Default ({name})'**
  String userPlaceholderDefault(String name);

  /// Placeholder; user name
  ///
  /// In en, this message translates to:
  /// **'From ~/.ssh/config ({name})'**
  String userPlaceholderFromConfig(String name);

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// Field label: SSH private key
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get key;

  /// Placeholder
  ///
  /// In en, this message translates to:
  /// **'Use ssh-agent'**
  String get keyPlaceholder;

  /// Hint; user@host:port
  ///
  /// In en, this message translates to:
  /// **'From ~/.ssh/config: {summary}'**
  String fromSshConfig(String summary);

  /// Tooltip
  ///
  /// In en, this message translates to:
  /// **'Hosts from ~/.ssh/config'**
  String get hostsFromSshConfig;

  /// Menu placeholder
  ///
  /// In en, this message translates to:
  /// **'No hosts in ~/.ssh/config'**
  String get noHostsInSshConfig;

  /// Tooltip
  ///
  /// In en, this message translates to:
  /// **'Choose a private key'**
  String get chooseKey;

  /// Menu item
  ///
  /// In en, this message translates to:
  /// **'Use ssh-agent and ~/.ssh/config'**
  String get useAgent;

  /// Menu item
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get chooseFile;

  /// File panel button
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get choose;

  /// Section title
  ///
  /// In en, this message translates to:
  /// **'Port Forwarding Rules'**
  String get forwardRules;

  /// Label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get ruleName;

  /// Label
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get ruleLocal;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Add Rule'**
  String get addRule;

  /// Tooltip
  ///
  /// In en, this message translates to:
  /// **'Delete Rule'**
  String get deleteRule;

  /// Tooltip
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get dragToReorder;

  /// Switch label
  ///
  /// In en, this message translates to:
  /// **'Reconnect automatically if the connection drops (and after waking from sleep)'**
  String get autoReconnect;

  /// Section title
  ///
  /// In en, this message translates to:
  /// **'ssh Output'**
  String get sshOutput;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Status
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// Status
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get statusConnecting;

  /// Status
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get statusStopping;

  /// Status
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get statusStopped;

  /// Status
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get statusError;

  /// Status detail
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get detailConnecting;

  /// Status detail
  ///
  /// In en, this message translates to:
  /// **'Retrying in {seconds} s…'**
  String detailRetrying(int seconds);

  /// Status detail
  ///
  /// In en, this message translates to:
  /// **'Stopping…'**
  String get detailStopping;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Enter a host'**
  String get issueMissingHost;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Invalid SSH port'**
  String get issueInvalidSshPort;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'No port forwarding rules'**
  String get issueNoRules;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Invalid ports in “{rule}”'**
  String issueInvalidPorts(String rule);

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Missing remote host in “{rule}”'**
  String issueMissingRemoteHost(String rule);

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Local port {port} is used twice'**
  String issueDuplicateLocalPort(String port);

  /// Error
  ///
  /// In en, this message translates to:
  /// **'The host key changed (check ~/.ssh/known_hosts)'**
  String get issueHostKeyChanged;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Local port in use ({ports})'**
  String issueLocalPortInUse(String ports);

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Authentication failed (check the key or ssh-agent)'**
  String get issueAuthentication;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'SSH configuration error'**
  String get issueSshConfiguration;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'ssh exited (code {code})'**
  String issueSshExited(String code);

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get issueConnectionLost;

  /// Error
  ///
  /// In en, this message translates to:
  /// **'Cannot run ssh'**
  String get issueCannotRunSsh;

  /// Log
  ///
  /// In en, this message translates to:
  /// **'Woke from sleep: restarting the tunnel'**
  String get logWokeFromSleep;

  /// Log
  ///
  /// In en, this message translates to:
  /// **'A local port is in use by another process.'**
  String get logPortUsedByOther;

  /// Log
  ///
  /// In en, this message translates to:
  /// **'Cannot run ssh: {error}'**
  String logCannotRunSsh(String error);

  /// Log
  ///
  /// In en, this message translates to:
  /// **'Could not stop ssh process {pid}'**
  String logCouldNotStopProcess(String pid);

  /// Default configuration name
  ///
  /// In en, this message translates to:
  /// **'Connection {index}'**
  String defaultConfigName(int index);

  /// Fallback configuration name
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get fallbackConfigName;

  /// Default rule name
  ///
  /// In en, this message translates to:
  /// **'Rule {index}'**
  String defaultRuleName(int index);

  /// Quit dialog message
  ///
  /// In en, this message translates to:
  /// **'Tunnels you keep running stay available after SSH Túnel quits, and the app picks them up again the next time it opens.'**
  String get quitMessage;

  /// Quit dialog button
  ///
  /// In en, this message translates to:
  /// **'Close Tunnels'**
  String get closeTunnels;

  /// Quit dialog button
  ///
  /// In en, this message translates to:
  /// **'Keep Running'**
  String get keepRunning;

  /// Quit dialog checkbox
  ///
  /// In en, this message translates to:
  /// **'Don’t ask again'**
  String get dontAskAgain;

  /// Tooltip
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Settings label
  ///
  /// In en, this message translates to:
  /// **'When quitting with open tunnels:'**
  String get quitBehaviorLabel;

  /// Settings option
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get quitAsk;

  /// Settings option
  ///
  /// In en, this message translates to:
  /// **'Close the tunnels'**
  String get quitClose;

  /// Settings option
  ///
  /// In en, this message translates to:
  /// **'Keep the tunnels running'**
  String get quitKeep;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Quit dialog title
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Close the open tunnel before quitting?} other{Close the {count} open tunnels before quitting?}}'**
  String quitTitle(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ca', 'en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ca':
      return AppLocalizationsCa();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

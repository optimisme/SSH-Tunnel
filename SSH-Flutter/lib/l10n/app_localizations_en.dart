// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SSH Túnel';

  @override
  String get sidebarTitle => 'SSH Configurations';

  @override
  String get addConfiguration => 'Add Configuration';

  @override
  String get add => 'Add';

  @override
  String get deleteConfiguration => 'Delete Configuration';

  @override
  String deleteConfirmTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get deleteConfirmMessage =>
      'If the tunnel is active, it will be stopped.';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get noSelection => 'Select a configuration or add a new one.';

  @override
  String get configurationName => 'Configuration Name';

  @override
  String get sshConnection => 'SSH Connection';

  @override
  String get host => 'Host';

  @override
  String get hostPlaceholder => 'Host name, IP or ~/.ssh/config alias';

  @override
  String get user => 'User';

  @override
  String userPlaceholderDefault(String name) {
    return 'Default ($name)';
  }

  @override
  String userPlaceholderFromConfig(String name) {
    return 'From ~/.ssh/config ($name)';
  }

  @override
  String get port => 'Port';

  @override
  String get key => 'Key';

  @override
  String get keyPlaceholder => 'Use ssh-agent';

  @override
  String fromSshConfig(String summary) {
    return 'From ~/.ssh/config: $summary';
  }

  @override
  String get hostsFromSshConfig => 'Hosts from ~/.ssh/config';

  @override
  String get noHostsInSshConfig => 'No hosts in ~/.ssh/config';

  @override
  String get chooseKey => 'Choose a private key';

  @override
  String get useAgent => 'Use ssh-agent and ~/.ssh/config';

  @override
  String get chooseFile => 'Choose…';

  @override
  String get choose => 'Choose';

  @override
  String get forwardRules => 'Port Forwarding Rules';

  @override
  String get ruleName => 'Name';

  @override
  String get ruleLocal => 'Local';

  @override
  String get addRule => 'Add Rule';

  @override
  String get deleteRule => 'Delete Rule';

  @override
  String get dragToReorder => 'Drag to reorder';

  @override
  String get autoReconnect =>
      'Reconnect automatically if the connection drops (and after waking from sleep)';

  @override
  String get sshOutput => 'ssh Output';

  @override
  String get clear => 'Clear';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get refresh => 'Refresh';

  @override
  String get statusActive => 'Active';

  @override
  String get statusConnecting => 'Connecting';

  @override
  String get statusStopping => 'Stopping';

  @override
  String get statusStopped => 'Stopped';

  @override
  String get statusError => 'Error';

  @override
  String get detailConnecting => 'Connecting…';

  @override
  String detailRetrying(int seconds) {
    return 'Retrying in $seconds s…';
  }

  @override
  String get detailStopping => 'Stopping…';

  @override
  String get issueMissingHost => 'Enter a host';

  @override
  String get issueInvalidSshPort => 'Invalid SSH port';

  @override
  String get issueNoRules => 'No port forwarding rules';

  @override
  String issueInvalidPorts(String rule) {
    return 'Invalid ports in “$rule”';
  }

  @override
  String issueMissingRemoteHost(String rule) {
    return 'Missing remote host in “$rule”';
  }

  @override
  String issueDuplicateLocalPort(String port) {
    return 'Local port $port is used twice';
  }

  @override
  String get issueHostKeyChanged =>
      'The host key changed (check ~/.ssh/known_hosts)';

  @override
  String issueLocalPortInUse(String ports) {
    return 'Local port in use ($ports)';
  }

  @override
  String get issueAuthentication =>
      'Authentication failed (check the key or ssh-agent)';

  @override
  String get issueSshConfiguration => 'SSH configuration error';

  @override
  String issueSshExited(String code) {
    return 'ssh exited (code $code)';
  }

  @override
  String get issueConnectionLost => 'Connection lost';

  @override
  String get issueCannotRunSsh => 'Cannot run ssh';

  @override
  String get logWokeFromSleep => 'Woke from sleep: restarting the tunnel';

  @override
  String get logPortUsedByOther => 'A local port is in use by another process.';

  @override
  String logCannotRunSsh(String error) {
    return 'Cannot run ssh: $error';
  }

  @override
  String logCouldNotStopProcess(String pid) {
    return 'Could not stop ssh process $pid';
  }

  @override
  String defaultConfigName(int index) {
    return 'Connection $index';
  }

  @override
  String get fallbackConfigName => 'Connection';

  @override
  String defaultRuleName(int index) {
    return 'Rule $index';
  }

  @override
  String get quitMessage =>
      'Tunnels you keep running stay available after SSH Túnel quits, and the app picks them up again the next time it opens.';

  @override
  String get closeTunnels => 'Close Tunnels';

  @override
  String get keepRunning => 'Keep Running';

  @override
  String get dontAskAgain => 'Don’t ask again';

  @override
  String get settings => 'Settings';

  @override
  String get quitBehaviorLabel => 'When quitting with open tunnels:';

  @override
  String get quitAsk => 'Ask';

  @override
  String get quitClose => 'Close the tunnels';

  @override
  String get quitKeep => 'Keep the tunnels running';

  @override
  String get done => 'Done';

  @override
  String quitTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Close the $count open tunnels before quitting?',
      one: 'Close the open tunnel before quitting?',
    );
    return '$_temp0';
  }
}

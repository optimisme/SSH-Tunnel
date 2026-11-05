// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Catalan Valencian (`ca`).
class AppLocalizationsCa extends AppLocalizations {
  AppLocalizationsCa([String locale = 'ca']) : super(locale);

  @override
  String get appTitle => 'SSH Túnel';

  @override
  String get sidebarTitle => 'Configuracions SSH';

  @override
  String get addConfiguration => 'Afegeix una configuració';

  @override
  String get add => 'Afegeix';

  @override
  String get deleteConfiguration => 'Elimina la configuració';

  @override
  String deleteConfirmTitle(String name) {
    return 'Vols eliminar «$name»?';
  }

  @override
  String get deleteConfirmMessage => 'Si el túnel és actiu, s’aturarà.';

  @override
  String get delete => 'Elimina';

  @override
  String get cancel => 'Cancel·la';

  @override
  String get noSelection =>
      'Selecciona una configuració o afegeix-ne una de nova.';

  @override
  String get configurationName => 'Nom de la configuració';

  @override
  String get sshConnection => 'Connexió SSH';

  @override
  String get host => 'Host';

  @override
  String get hostPlaceholder => 'Nom del host, IP o àlies de ~/.ssh/config';

  @override
  String get user => 'Usuari';

  @override
  String userPlaceholderDefault(String name) {
    return 'Per omissió ($name)';
  }

  @override
  String userPlaceholderFromConfig(String name) {
    return 'De ~/.ssh/config ($name)';
  }

  @override
  String get port => 'Port';

  @override
  String get key => 'Clau';

  @override
  String get keyPlaceholder => 'Usa l’ssh-agent';

  @override
  String fromSshConfig(String summary) {
    return 'De ~/.ssh/config: $summary';
  }

  @override
  String get hostsFromSshConfig => 'Hosts de ~/.ssh/config';

  @override
  String get noHostsInSshConfig => 'No hi ha hosts a ~/.ssh/config';

  @override
  String get chooseKey => 'Tria una clau privada';

  @override
  String get useAgent => 'Usa l’ssh-agent i ~/.ssh/config';

  @override
  String get chooseFile => 'Tria…';

  @override
  String get choose => 'Tria';

  @override
  String get forwardRules => 'Regles de reenviament de port';

  @override
  String get ruleName => 'Nom';

  @override
  String get ruleLocal => 'Local';

  @override
  String get addRule => 'Afegeix una regla';

  @override
  String get deleteRule => 'Elimina la regla';

  @override
  String get dragToReorder => 'Arrossega per reordenar';

  @override
  String get autoReconnect =>
      'Reconnecta automàticament si es perd la connexió (i en sortir del repòs)';

  @override
  String get sshOutput => 'Sortida d’ssh';

  @override
  String get clear => 'Neteja';

  @override
  String get connect => 'Connecta';

  @override
  String get disconnect => 'Desconnecta';

  @override
  String get refresh => 'Actualitza';

  @override
  String get statusActive => 'Actiu';

  @override
  String get statusConnecting => 'Connectant';

  @override
  String get statusStopping => 'Aturant';

  @override
  String get statusStopped => 'Aturat';

  @override
  String get statusError => 'Error';

  @override
  String get detailConnecting => 'Connectant…';

  @override
  String detailRetrying(int seconds) {
    return 'Nou intent d’aquí a $seconds s…';
  }

  @override
  String get detailStopping => 'Aturant…';

  @override
  String get issueMissingHost => 'Indica un host';

  @override
  String get issueInvalidSshPort => 'El port SSH no és vàlid';

  @override
  String get issueNoRules => 'No hi ha cap regla de reenviament de port';

  @override
  String issueInvalidPorts(String rule) {
    return 'Ports no vàlids a «$rule»';
  }

  @override
  String issueMissingRemoteHost(String rule) {
    return 'Falta el host remot a «$rule»';
  }

  @override
  String issueDuplicateLocalPort(String port) {
    return 'El port local $port està repetit';
  }

  @override
  String get issueHostKeyChanged =>
      'La clau del host ha canviat (revisa ~/.ssh/known_hosts)';

  @override
  String issueLocalPortInUse(String ports) {
    return 'Port local ocupat ($ports)';
  }

  @override
  String get issueAuthentication =>
      'Error d’autenticació (revisa la clau o l’ssh-agent)';

  @override
  String get issueSshConfiguration => 'Error de configuració d’SSH';

  @override
  String issueSshExited(String code) {
    return 'ssh ha acabat (codi $code)';
  }

  @override
  String get issueConnectionLost => 'S’ha perdut la connexió';

  @override
  String get issueCannotRunSsh => 'No es pot executar ssh';

  @override
  String get logWokeFromSleep => 'Sortida del repòs: es reinicia el túnel';

  @override
  String get logPortUsedByOther =>
      'Un port local està ocupat per un altre procés.';

  @override
  String logCannotRunSsh(String error) {
    return 'No es pot executar ssh: $error';
  }

  @override
  String logCouldNotStopProcess(String pid) {
    return 'No s’ha pogut aturar el procés ssh $pid';
  }

  @override
  String defaultConfigName(int index) {
    return 'Connexió $index';
  }

  @override
  String get fallbackConfigName => 'Connexió';

  @override
  String defaultRuleName(int index) {
    return 'Regla $index';
  }

  @override
  String get quitMessage =>
      'Els túnels que mantinguis oberts continuaran funcionant quan surtis de l’SSH Túnel, i l’app els recuperarà la pròxima vegada que l’obris.';

  @override
  String get closeTunnels => 'Tanca els túnels';

  @override
  String get keepRunning => 'Mantén-los oberts';

  @override
  String get dontAskAgain => 'No ho tornis a preguntar';

  @override
  String get settings => 'Configuració';

  @override
  String get quitBehaviorLabel => 'En sortir amb túnels oberts:';

  @override
  String get quitAsk => 'Preguntar';

  @override
  String get quitClose => 'Tancar els túnels';

  @override
  String get quitKeep => 'Mantenir els túnels oberts';

  @override
  String get done => 'Fet';

  @override
  String quitTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vols tancar els $count túnels oberts abans de sortir?',
      one: 'Vols tancar el túnel obert abans de sortir?',
    );
    return '$_temp0';
  }
}

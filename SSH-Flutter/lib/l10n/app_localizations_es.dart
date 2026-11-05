// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'SSH Túnel';

  @override
  String get sidebarTitle => 'Configuraciones SSH';

  @override
  String get addConfiguration => 'Añadir configuración';

  @override
  String get add => 'Añadir';

  @override
  String get deleteConfiguration => 'Eliminar configuración';

  @override
  String deleteConfirmTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get deleteConfirmMessage => 'Si el túnel está activo, se detendrá.';

  @override
  String get delete => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get noSelection => 'Selecciona una configuración o añade una nueva.';

  @override
  String get configurationName => 'Nombre de la configuración';

  @override
  String get sshConnection => 'Conexión SSH';

  @override
  String get host => 'Host';

  @override
  String get hostPlaceholder => 'Nombre del host, IP o alias de ~/.ssh/config';

  @override
  String get user => 'Usuario';

  @override
  String userPlaceholderDefault(String name) {
    return 'Por omisión ($name)';
  }

  @override
  String userPlaceholderFromConfig(String name) {
    return 'De ~/.ssh/config ($name)';
  }

  @override
  String get port => 'Puerto';

  @override
  String get key => 'Clave';

  @override
  String get keyPlaceholder => 'Usar ssh-agent';

  @override
  String fromSshConfig(String summary) {
    return 'De ~/.ssh/config: $summary';
  }

  @override
  String get hostsFromSshConfig => 'Hosts de ~/.ssh/config';

  @override
  String get noHostsInSshConfig => 'No hay hosts en ~/.ssh/config';

  @override
  String get chooseKey => 'Elegir una clave privada';

  @override
  String get useAgent => 'Usar ssh-agent y ~/.ssh/config';

  @override
  String get chooseFile => 'Elegir…';

  @override
  String get choose => 'Elegir';

  @override
  String get forwardRules => 'Reglas de reenvío de puertos';

  @override
  String get ruleName => 'Nombre';

  @override
  String get ruleLocal => 'Local';

  @override
  String get addRule => 'Añadir regla';

  @override
  String get deleteRule => 'Eliminar regla';

  @override
  String get dragToReorder => 'Arrastrar para reordenar';

  @override
  String get autoReconnect =>
      'Volver a conectar automáticamente si se pierde la conexión (y al salir del reposo)';

  @override
  String get sshOutput => 'Salida de ssh';

  @override
  String get clear => 'Borrar';

  @override
  String get connect => 'Conectar';

  @override
  String get disconnect => 'Desconectar';

  @override
  String get refresh => 'Actualizar';

  @override
  String get statusActive => 'Activo';

  @override
  String get statusConnecting => 'Conectando';

  @override
  String get statusStopping => 'Deteniendo';

  @override
  String get statusStopped => 'Detenido';

  @override
  String get statusError => 'Error';

  @override
  String get detailConnecting => 'Conectando…';

  @override
  String detailRetrying(int seconds) {
    return 'Reintentando en $seconds s…';
  }

  @override
  String get detailStopping => 'Deteniendo…';

  @override
  String get issueMissingHost => 'Introduce un host';

  @override
  String get issueInvalidSshPort => 'El puerto SSH no es válido';

  @override
  String get issueNoRules => 'No hay reglas de reenvío de puertos';

  @override
  String issueInvalidPorts(String rule) {
    return 'Puertos no válidos en «$rule»';
  }

  @override
  String issueMissingRemoteHost(String rule) {
    return 'Falta el host remoto en «$rule»';
  }

  @override
  String issueDuplicateLocalPort(String port) {
    return 'El puerto local $port está repetido';
  }

  @override
  String get issueHostKeyChanged =>
      'La clave del host ha cambiado (revisa ~/.ssh/known_hosts)';

  @override
  String issueLocalPortInUse(String ports) {
    return 'Puerto local en uso ($ports)';
  }

  @override
  String get issueAuthentication =>
      'Error de autenticación (revisa la clave o ssh-agent)';

  @override
  String get issueSshConfiguration => 'Error de configuración de SSH';

  @override
  String issueSshExited(String code) {
    return 'ssh ha terminado (código $code)';
  }

  @override
  String get issueConnectionLost => 'Se ha perdido la conexión';

  @override
  String get issueCannotRunSsh => 'No se puede ejecutar ssh';

  @override
  String get logWokeFromSleep => 'Fin del reposo: se reinicia el túnel';

  @override
  String get logPortUsedByOther => 'Otro proceso está usando un puerto local.';

  @override
  String logCannotRunSsh(String error) {
    return 'No se puede ejecutar ssh: $error';
  }

  @override
  String logCouldNotStopProcess(String pid) {
    return 'No se ha podido detener el proceso ssh $pid';
  }

  @override
  String defaultConfigName(int index) {
    return 'Conexión $index';
  }

  @override
  String get fallbackConfigName => 'Conexión';

  @override
  String defaultRuleName(int index) {
    return 'Regla $index';
  }

  @override
  String get quitMessage =>
      'Los túneles que mantengas abiertos seguirán funcionando al salir de SSH Túnel, y la app los recuperará la próxima vez que la abras.';

  @override
  String get closeTunnels => 'Cerrar túneles';

  @override
  String get keepRunning => 'Mantenerlos abiertos';

  @override
  String get dontAskAgain => 'No volver a preguntar';

  @override
  String get settings => 'Ajustes';

  @override
  String get quitBehaviorLabel => 'Al salir con túneles abiertos:';

  @override
  String get quitAsk => 'Preguntar';

  @override
  String get quitClose => 'Cerrar los túneles';

  @override
  String get quitKeep => 'Mantener los túneles abiertos';

  @override
  String get done => 'OK';

  @override
  String quitTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Cerrar los $count túneles abiertos antes de salir?',
      one: '¿Cerrar el túnel abierto antes de salir?',
    );
    return '$_temp0';
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mdm_client_base/apk_manager_screen.dart';
import 'package:mdm_client_base/app_blocker_settings_screen.dart';
import 'package:mdm_client_base/home_screen.dart';
import 'package:mdm_client_base/login_screen.dart';
import 'package:mdm_client_base/notification_service.dart';
import 'package:mdm_client_base/provisioning_status_screen.dart';
import 'package:mdm_client_base/reports_screen.dart';
import 'package:mdm_client_base/settings_screen.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  final prefs = await SharedPreferences.getInstance();
  final bool isConfigured = (prefs.getString('serial_number') ?? '').isNotEmpty;
  final String initialRoute = isConfigured ? '/' : '/settings';

  await NotificationService.instance.initialize();
  await initializeService();

  runApp(
    ChangeNotifierProvider(
      create: (_) => DeviceService(),
      child: MyApp(initialRoute: initialRoute),
    ),
  );
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final logger = Logger('BackgroundService');
  logger.info('Serviço em segundo plano iniciado: ${DateTime.now()}');

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    final deviceService = DeviceService();
    await deviceService.initialize();

    final prefs = await SharedPreferences.getInstance();
    final dataInterval = prefs.getInt('data_interval') ?? 10;
    final heartbeatInterval = prefs.getInt('heartbeat_interval') ?? 3;
    final commandCheckInterval = prefs.getInt('command_check_interval') ?? 1;

    final now = DateTime.now();
    final minutes = now.minute;

    if (minutes % dataInterval == 0) {
      final result = await deviceService.sendDeviceData();
      logger.info('Envio de dados: $result');
    }

    if (minutes % heartbeatInterval == 0) {
      final result = await deviceService.sendHeartbeat();
      logger.info('Heartbeat: $result');
    }

    if (minutes % commandCheckInterval == 0) {
      await deviceService.checkForCommands();
    }
  });
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Client Base',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const ImprovedLoginScreen(),
        '/home': (context) => const ImprovedHomeScreen(),
        '/provisioning_status': (context) => const ImprovedProvisioningScreen(),
        '/apk_manager': (context) => const ApkManagerScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/app_blocker': (context) => const AppBlockerSettingsScreen(),
        '/reports': (context) => const ReportsScreen(),
      },
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 2,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
        ),
      ),
    );
  }
}

class DeviceService with ChangeNotifier {
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');
  final Logger logger = Logger('DeviceService');

  String _serverUrl = 'http://192.168.0.183:3000';
  String _authToken = '';
  Map<String, dynamic> _deviceInfo = {};
  bool _isConnected = false;
  bool _isAdmin = false;
  int _batteryLevel = 0;
  DateTime _lastSync = DateTime.now();
  bool _hasLocationPermission = false;
  bool _hasNotificationPermission = false;

  String get serverUrl => _serverUrl;
  Map<String, dynamic> get deviceInfo => _deviceInfo;
  bool get isConnected => _isConnected;
  bool get isAdmin => _isAdmin;
  int get batteryLevel => _batteryLevel;
  DateTime get lastSync => _lastSync;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get hasNotificationPermission => _hasNotificationPermission;

  DeviceService() {
    initialize();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final serverHost = prefs.getString('server_host') ?? '192.168.0.183';
    final serverPort = prefs.getString('server_port') ?? '3000';
    _serverUrl = 'http://$serverHost:$serverPort';
    _authToken = prefs.getString('auth_token') ?? '';

    await _updateDeviceStatus(checkAdmin: false, checkPermissions: false);
    logger.info('DeviceService inicializado. Servidor: $_serverUrl');
    notifyListeners();
  }

  Future<void> _updateDeviceStatus({bool checkAdmin = true, bool checkPermissions = true}) async {
    final connectivity = Connectivity();
    final battery = Battery();
    final networkInfo = NetworkInfo();

    _isConnected = await connectivity.checkConnectivity() != ConnectivityResult.none;
    _batteryLevel = await battery.batteryLevel;

    if (checkAdmin) {
      try {
        final bool isDeviceOwner = await platform.invokeMethod('isDeviceOwnerOrProfileOwner');
        if (isDeviceOwner) {
          _isAdmin = true;
          logger.info("O aplicativo é Dono do Dispositivo (Device Owner).");
        } else {
          final bool isDeviceAdmin = await platform.invokeMethod('isDeviceAdmin');
          _isAdmin = isDeviceAdmin;
          if (isDeviceAdmin) {
            logger.info("O aplicativo é Administrador de Dispositivo (Device Admin).");
          } else {
            logger.info("Não é Dono nem Administrador. Aguardando ação do usuário.");
          }
        }
      } catch (e) {
        _isAdmin = false;
        logger.severe("Erro ao verificar status de admin: $e");
      }
    }

    if (checkPermissions) {
      try {
        _hasLocationPermission = await platform.invokeMethod('hasLocationPermission');
        _hasNotificationPermission = await platform.invokeMethod('hasNotificationPermission');
        logger.info("Permissões: Localização=$_hasLocationPermission, Notificação=$_hasNotificationPermission");
      } catch (e) {
        _hasLocationPermission = false;
        _hasNotificationPermission = false;
        logger.severe("Erro ao verificar permissões: $e");
      }
    }

    if (!kIsWeb && Platform.isAndroid) {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final androidInfo = await deviceInfoPlugin.androidInfo;
      final prefs = await SharedPreferences.getInstance();

      String hardwareSerialNumber = 'N/A';
      try {
        hardwareSerialNumber = androidInfo.serialNumber;
      } catch (e) {
        logger.warning("Não foi possível ler o serial number do hardware: $e. A usar o valor guardado.");
      }

      final serialNumber = (hardwareSerialNumber.isNotEmpty && hardwareSerialNumber != 'unknown' && hardwareSerialNumber != 'N/A')
          ? hardwareSerialNumber
          : prefs.getString('serial_number') ?? 'N/A';

      _deviceInfo = {
        'device_name': androidInfo.name,
        'device_model': androidInfo.model,
        'device_id': androidInfo.display,
        'serial_number': serialNumber,
        'imei': prefs.getString('imei') ?? 'N/A',
        'battery': _batteryLevel,
        'network': await networkInfo.getWifiName() ?? 'N/A',
        'host': androidInfo.host,
        'sector': prefs.getString('sector') ?? 'N/A',
        'floor': prefs.getString('floor') ?? 'N/A',
        'mac_address_radio': await networkInfo.getWifiBSSID() ?? 'N/A',
        'last_sync': prefs.getString('last_sync') ?? 'N/A',
        'secure_android_id': androidInfo.id,
        'ip_address': await networkInfo.getWifiIP() ?? 'N/A',
        'wifi_ipv6': await networkInfo.getWifiIPv6() ?? 'N/A',
        'wifi_gateway_ip': await networkInfo.getWifiGatewayIP() ?? 'N/A',
        'wifi_broadcast': await networkInfo.getWifiBroadcast() ?? 'N/A',
        'wifi_submask': await networkInfo.getWifiSubmask() ?? 'N/A',
        'last_seen': DateTime.now().toIso8601String(),
      };
    }
    notifyListeners();
  }

  Future<bool> requestDeviceAdmin() async {
    try {
      await platform.invokeMethod('requestDeviceAdmin', {
        'explanation': 'Este aplicativo precisa de permissões de administrador para gerenciar o dispositivo.'
      });
      final bool isDeviceAdmin = await platform.invokeMethod('isDeviceAdmin');
      _isAdmin = isDeviceAdmin;
      notifyListeners();
      logger.info("Permissão de administrador ${isDeviceAdmin ? 'concedida' : 'recusada'}");
      return isDeviceAdmin;
    } catch (e) {
      logger.severe("Erro ao solicitar permissão de administrador: $e");
      return false;
    }
  }

  Future<bool> requestLocationPermission() async {
    try {
      final bool granted = await platform.invokeMethod('requestLocationPermission');
      _hasLocationPermission = granted;
      notifyListeners();
      logger.info("Permissão de localização ${granted ? 'concedida' : 'recusada'}");
      return granted;
    } catch (e) {
      logger.severe("Erro ao solicitar permissão de localização: $e");
      return false;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final bool granted = await platform.invokeMethod('requestNotificationPermission');
      _hasNotificationPermission = granted;
      notifyListeners();
      logger.info("Permissão de notificação ${granted ? 'concedida' : 'recusada'}");
      return granted;
    } catch (e) {
      logger.severe("Erro ao solicitar permissão de notificação: $e");
      return false;
    }
  }

  Future<bool> login(String password) async {
    if (password == 'hap@2025') {
      logger.info("Login bem-sucedido. O token guardado será utilizado.");
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    _authToken = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }

  Future<void> saveSettings({
    required String imei,
    required String serial,
    required String sector,
    required String floor,
    required String serverHost,
    required String serverPort,
    required String token,
    required int dataInterval,
    required int heartbeatInterval,
    required int commandCheckInterval,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('imei', imei);
    await prefs.setString('serial_number', serial);
    await prefs.setString('sector', sector);
    await prefs.setString('floor', floor);
    await prefs.setString('server_host', serverHost);
    await prefs.setString('server_port', serverPort);
    await prefs.setString('auth_token', token);
    await prefs.setInt('data_interval', dataInterval);
    await prefs.setInt('heartbeat_interval', heartbeatInterval);
    await prefs.setInt('command_check_interval', commandCheckInterval);
    await initialize();
  }

  Future<String> sendDeviceData() async {
    await _updateDeviceStatus();
    if (!_isConnected || _authToken.isEmpty) {
      return 'Sem conexão ou token inválido.';
    }
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/devices/data'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_authToken'},
        body: jsonEncode(_deviceInfo),
      );
      if (response.statusCode == 200) {
        _lastSync = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_sync', _lastSync.toIso8601String());
        notifyListeners();
        return 'Dados enviados com sucesso.';
      }
      return 'Erro ${response.statusCode}: ${response.body}';
    } catch (e) {
      return 'Erro de comunicação: $e';
    }
  }

  Future<String> sendHeartbeat() async {
    if (!_isConnected || _authToken.isEmpty) {
      return 'Heartbeat falhou: Sem conexão ou token inválido.';
    }
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/devices/heartbeat'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_authToken'},
        body: jsonEncode({'device_id': _deviceInfo['device_id']}),
      );
      if (response.statusCode == 200) {
        return 'Heartbeat enviado com sucesso.';
      }
      return 'Falha no Heartbeat: ${response.statusCode}';
    } catch (e) {
      return 'Erro de comunicação no Heartbeat: $e';
    }
  }

  Future<void> checkForCommands() async {
    if (!_isConnected || _authToken.isEmpty) {
      logger.warning('Verificação de comandos falhou: Sem conexão ou token.');
      return;
    }
    try {
      final serialNumber = _deviceInfo['serial_number'];
      final response = await http.get(
        Uri.parse('$_serverUrl/api/devices/commands?serial_number=$serialNumber'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );

      if (response.statusCode == 200) {
        final commands = jsonDecode(response.body) as List;
        logger.info('${commands.length} comandos recebidos.');
        for (var command in commands) {
          await _executeCommand(command);
        }
      } else {
        logger.severe('Falha ao buscar comandos: ${response.statusCode}');
      }
    } catch (e) {
      logger.severe('Erro de comunicação ao buscar comandos: $e');
    }
  }

  Future<void> _executeCommand(Map<String, dynamic> command) async {
    final type = command['command_type'];
    final params = command['parameters'] as Map<String, dynamic>;
    logger.info('A executar comando: $type com parâmetros: $params');

    try {
      switch (type) {
        case 'lock_device':
          await platform.invokeMethod('lockDevice');
          break;
        case 'wipe_data':
          await platform.invokeMethod('wipeData');
          break;
        case 'install_app':
          final apkUrl = params['apk_url'];
          logger.info('Comando para instalar app de $apkUrl recebido.');
          break;
        case 'restrict_settings':
          final restrict = params['restrict'] as bool;
          await restrictSettings(restrict);
          break;
        default:
          logger.warning('Comando desconhecido: $type');
      }
    } catch (e) {
      logger.severe('Erro ao executar comando $type: $e');
    }
  }

  Future<void> restrictSettings(bool restrict) async {
    try {
      await platform.invokeMethod('restrictSettings', {'restrict': restrict});
      logger.info('Configurações ${restrict ? "restringidas" : "liberadas"}.');
    } catch (e) {
      logger.severe('Erro ao alterar restrição de configurações: $e');
    }
  }

  Future<String> getMacAddress() async {
    try {
      return await NetworkInfo().getWifiBSSID() ?? 'N/A';
    } catch (e) {
      logger.severe('Não foi possível obter o MAC Address: $e');
      return 'Error';
    }
  }

  Future<String> getIpAddress() async {
    try {
      return await NetworkInfo().getWifiIP() ?? 'N/A';
    } catch (e) {
      logger.severe('Não foi possível obter o Endereço IP: $e');
      return 'Error';
    }
  }

  Future<String> getWifiName() async {
    try {
      return await NetworkInfo().getWifiName() ?? 'N/A';
    } catch (e) {
      logger.severe('Não foi possível obter o nome da rede Wi-Fi: $e');
      return 'Error';
    }
  }
}
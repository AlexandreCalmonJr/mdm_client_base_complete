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
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:mdm_client_base/login_screen.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apk_manager_screen.dart';
// Placeholder imports (replace with actual implementations)
import 'notification_service.dart';
import 'provisioning_status_screen.dart';

void main() async {
  // Configurar logger
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Inicializar serviços
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  await initializeService();

  runApp(const MyApp());
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
      onBackground: onIosBackground,
    ),
  );
  await service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final logger = Logger('BackgroundService');

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  final deviceService = DeviceService();
  await deviceService.checkConnectivity();
  await deviceService.initialize();
  await deviceService._refreshMacAddress();
  await deviceService.updateDeviceInfo();
  await deviceService.setAuthToken(deviceService.authToken);
  final prefs = await SharedPreferences.getInstance();
  final dataInterval = prefs.getInt('data_interval') ?? 10;
  final heartbeatInterval = prefs.getInt('heartbeat_interval') ?? 3;
  final commandCheckInterval = prefs.getInt('command_check_interval') ?? 1;

  logger.info('Serviço em segundo plano iniciado: ${DateTime.now()}');
  logger.info('Intervalos configurados: Data: $dataInterval min, Heartbeat: $heartbeatInterval min, Comandos: $commandCheckInterval min');
  int heartbeatFailureCount = prefs.getInt('heartbeat_failure_count') ?? 0;
  Timer.periodic(const Duration(minutes: 1), (_) async {
    final now = DateTime.now();
    final minutesSinceStart = now.difference(DateTime(now.year, now.month, now.day)).inMinutes;

    if (minutesSinceStart % dataInterval == 0) {
      final result = await deviceService.sendDeviceData();
      logger.info('Dados enviados: $result');
    }

    if (minutesSinceStart % heartbeatInterval == 0) {
      final result = await deviceService.sendHeartbeat();
      logger.info('Heartbeat: $result${heartbeatFailureCount > 0 ? ', Falhas: $heartbeatFailureCount' : ''}');
      if (result != 'Heartbeat enviado com sucesso') {
        heartbeatFailureCount++;
        await prefs.setString('last_heartbeat_error', '$result às ${DateTime.now().toIso8601String()}');
        await prefs.setInt('heartbeat_failure_count', heartbeatFailureCount);
      } else {
        heartbeatFailureCount = 0;
        await prefs.remove('last_heartbeat_error');
        await prefs.setInt('heartbeat.vaCount', heartbeatFailureCount);
      }
    }

    if (minutesSinceStart % commandCheckInterval == 0) {
      await deviceService.checkForCommands();
    }

    if (service is AndroidServiceInstance && !await service.isForegroundService()) {
      logger.warning('Serviço parou inesperadamente. Tentando reiniciar...');
      await FlutterBackgroundService().startService();
    }
  });
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Client Base',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      initialRoute: '/',
      routes: _buildRoutes(),
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      fontFamily: 'Inter', // Adiciona a fonte Inter
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
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Map<String, WidgetBuilder> _buildRoutes() {
    return {
      '/': (context) => const LoginScreen(),
      '/home': (context) => HomePage(deviceService: DeviceService()),
      '/provisioning_status': (context) => const ProvisioningStatusScreen(),
      '/apk_manager': (context) => const ApkManagerScreen(),
      '/settings': (context) => const MDMClientHome(),
    };
  }
}
class HomePage extends StatelessWidget {
  final DeviceService deviceService;
  static final Logger _logger = Logger('HomePage');

  const HomePage({super.key, required this.deviceService});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(context, colorScheme),
      body: _buildBody(context, colorScheme),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    return AppBar(
      title: const Text(
        'MDM Client Base',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withOpacity(0.1),
              colorScheme.secondary.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.surfaceContainerHighest.withOpacity(0.3),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderCard(context, colorScheme),
              const SizedBox(height: 32),
              _buildMenuSection(context),
              const SizedBox(height: 20),
              _buildVersionInfo(context, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(
              Icons.security,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Gerenciamento de Dispositivos',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sistema de controle e monitoramento MDM',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildMenuCard(
          context: context,
          title: 'Status de Provisionamento',
          subtitle: 'Verificar status do dispositivo',
          icon: Icons.verified_user,
          color: Colors.green,
          onTap: () => _navigateToRoute(context, '/provisioning_status'),
        ),
        const SizedBox(height: 4),
        _buildMenuCard(
          context: context,
          title: 'Gerenciador de APKs',
          subtitle: 'Instalar e gerenciar aplicativos',
          icon: Icons.install_mobile,
          color: Colors.blue,
          onTap: () => _navigateToRoute(context, '/apk_manager'),
        ),
        const SizedBox(height: 4),
        _buildMenuCard(
          context: context,
          title: 'Configurações do Dispositivo',
          subtitle: 'Gerenciar configurações do dispositivo',
          icon: Icons.settings,
          color: Colors.orange,
          onTap: () => _navigateToSettings(context),
        ),
        const SizedBox(height: 4),
        // Novo card com botões de bloquear/desbloquear configurações
        _buildControlSettingsCard(context),
      ],
    );
  }

  // Novo método para o card de controle de configurações
  Widget _buildControlSettingsCard(BuildContext context) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Controle de Configurações',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _restrictSettings(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text(
                    'Bloquear',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 5),
                ElevatedButton(
                  onPressed: () => _unrestrictSettings(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text(
                    'Desbloquear',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionInfo(BuildContext context, ColorScheme colorScheme) {
    return Text(
      'MDM Client v2.0 - Desenvolvido por Allexandre Calmon - TI Bahia 2025',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildMenuCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 6,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              _buildIconContainer(icon, color),
              const SizedBox(width: 20),
              Expanded(child: _buildCardContent(context, title, subtitle)),
              _buildArrowIcon(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconContainer(IconData icon, Color color) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: 32,
        color: color,
      ),
    );
  }

  Widget _buildCardContent(BuildContext context, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildArrowIcon(BuildContext context) {
    return Icon(
      Icons.arrow_forward_ios,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: 20,
    );
  }

  // Métodos de navegação
  void _navigateToRoute(BuildContext context, String route) {
    _logger.info('Navegando para $route');
    Navigator.pushNamed(context, route);
  }

  Future<void> _navigateToSettings(BuildContext context) async {
    _logger.info('Abrindo configurações do dispositivo');
    try {
      await Navigator.pushNamed(context, '/settings');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações atualizadas com sucesso!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _logger.severe('Erro ao navegar para configurações: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao abrir configurações'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Métodos para bloquear/desbloquear configurações
  Future<void> _restrictSettings(BuildContext context) async {
    _logger.info('Tentando bloquear configurações do dispositivo');
    try {
      const platform = MethodChannel('com.example.mdm_client_base/device_policy');
      await platform.invokeMethod('restrictSettings', {'restrict': true});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações do dispositivo bloqueadas'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      _logger.info('Configurações bloqueadas com sucesso');
    } catch (e) {
      _logger.severe('Erro ao bloquear configurações: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao bloquear configurações: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _unrestrictSettings(BuildContext context) async {
    _logger.info('Tentando desbloquear configurações do dispositivo');
    try {
      const platform = MethodChannel('com.example.mdm_client_base/device_policy');
      await platform.invokeMethod('restrictSettings', {'restrict': false});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações do dispositivo desbloqueadas'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      _logger.info('Configurações desbloqueadas com sucesso');
    } catch (e) {
      _logger.severe('Erro ao desbloquear configurações: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao desbloquear configurações: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}


class DeviceService {
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');
  String serverUrl = 'http://192.168.0.183:3000';
  String authToken = '';
  final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final Battery battery = Battery();
  final Connectivity connectivity = Connectivity();
  final NetworkInfo networkInfo = NetworkInfo();
  final Logger logger = Logger('DeviceService');
  String? serialnumber;
  String? deviceId;
  Map<String, dynamic> deviceInfo = {};
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration timeout = Duration(seconds: 10);
  String? bssid;

  Future<void> initialize() async {
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final prefs = await SharedPreferences.getInstance();
    final imei = prefs.getString('imei') ?? 'N/A';
    final serialNumber = prefs.getString('serial_number') ?? 'N/A';
    final sector = prefs.getString('sector') ?? 'N/A';
    final floor = prefs.getString('floor') ?? 'N/A';
    final serverHost = prefs.getString('server_host') ?? '192.168.0.183';
    final serverPort = prefs.getString('server_port') ?? '3000';
    final lastSync = prefs.getString('last_sync') ?? 'N/A';
    authToken = prefs.getString('auth_token') ?? 'seu_token_aqui';
    await prefs.setString('auth_token', authToken);
    logger.info('authToken configurado: $authToken, serial_number: $serialNumber');
    final batteryLevel = await battery.batteryLevel;
    logger.info('authToken forçado: $authToken');

    await prefs.setString('auth_token', authToken);
    platform.setMethodCallHandler((call) async {
      if (call.method == "provisioningComplete") {
        logger.info("Provisionamento concluído: ${call.arguments['status']}");
        await sendDeviceData();
        await applyServerPolicies();
      } else if (call.method == "provisioningFailure" || call.method == "policyFailure") {
        logger.severe("Falha: ${call.method}, Erro: ${call.arguments['error']}");
        NotificationService.instance.showNotification(
          call.method == "provisioningFailure" ? "Falha no Provisionamento" : "Falha na Política",
          call.arguments['error'],
        );
      }
    });
    NotificationService.instance.initialize();

    serverUrl = 'http://$serverHost:$serverPort';

    deviceId = androidInfo.id;
    deviceInfo = {
      'device_name': androidInfo.name,
      'device_model': androidInfo.model,
      'device_id': androidInfo.id,
      'serial_number': serialNumber,
      'imei': imei,
      'sector': sector,
      'floor': floor,
      'mac_address_radio': await networkInfo.getWifiBSSID() ?? 'N/A',
      'ip_address': await networkInfo.getWifiIP() ?? 'N/A',
      'network': await networkInfo.getWifiName() ?? 'N/A',
      'battery': batteryLevel,
      'last_seen': DateTime.now().toIso8601String(),
      'last_sync': lastSync != 'N/A' ? lastSync : DateTime.now().toIso8601String(),
    };
    logger.info('Inicializado: serverUrl=$serverUrl, deviceId=$deviceId');
  }

  Future<void> _refreshMacAddress() async {
    try {
      if (await Permission.locationWhenInUse.request().isGranted) {
        final newMac = await networkInfo.getWifiBSSID() ?? await _getRealMacAddress();
        if (_isValidMacAddress(newMac)) {
          deviceInfo['mac_address_radio'] = newMac;
          logger.info('MAC address atualizado: $newMac');
        } else {
          logger.warning('MAC address inválido obtido: $newMac');
          deviceInfo['mac_address_radio'] = 'N/A';
        }
      } else {
        logger.warning('Permissão de localização negada');
        deviceInfo['mac_address_radio'] = 'Permissão negada';
      }
    } catch (e) {
      logger.severe('Erro ao atualizar MAC address: $e');
      deviceInfo['mac_address_radio'] = 'Error';
    }
  }

  Future<String> _getRealMacAddress() async {
    if (kIsWeb) {
      return 'N/A';
    } else {
      try {
        if (await Permission.location.request().isGranted) {
          final macAddress = await _invokeMethodChannel('getMacAddress');
          return macAddress ?? 'N/A';
        } else {
          logger.severe('Permissão ACCESS_WIFI_STATE negada');
          return 'Permissão negada';
        }
      } catch (e) {
        logger.severe('Erro ao obter MAC address: $e');
        return 'Error';
      }
    }
  }

  Future<String?> _invokeMethodChannel(String method, [Map<String, dynamic>? arguments]) async {
    try {
      logger.info('Tentando invocar método $method com argumentos: $arguments');
      final result = await platform.invokeMethod<String>(method, arguments);
      logger.info('Resultado do método $method: $result');
      return result;
    } on PlatformException catch (e) {
      logger.severe('Erro ao invocar método $method: ${e.message}, código: ${e.code}, detalhes: ${e.details}');
      rethrow;
    } catch (e) {
      logger.severe('Erro inesperado ao invocar método $method: $e');
      rethrow;
    }
  }

  bool _isValidMacAddress(String? mac) {
    if (mac == null || mac.isEmpty || mac == 'null') return false;

    final fakeMacs = [
      '02:00:00:00:00:00',
      '00:00:00:00:00:00',
      'ff:ff:ff:ff:ff:ff',
      'FF:FF:FF:FF:FF:FF',
    ];

    return !fakeMacs.contains(mac.toLowerCase());
  }

  Future<void> setServerUrl(String host, String port) async {
    serverUrl = 'http://$host:$port';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_host', host);
    await prefs.setString('server_port', port);
    logger.info('serverUrl atualizado: $serverUrl');
  }

  Future<void> setAuthToken(String token) async {
    authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', authToken);
    logger.info('authToken atualizado: $authToken');
  }

  Future<void> updateDeviceInfo() async {
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final prefs = await SharedPreferences.getInstance();
    final imei = prefs.getString('imei') ?? 'N/A';
    final serialNumber = prefs.getString('serial_number') ?? 'N/A';
    final sector = prefs.getString('sector') ?? 'N/A';
    final floor = prefs.getString('floor') ?? 'N/A';
    final batteryLevel = await battery.batteryLevel;

    deviceInfo['device_name'] = androidInfo.name;
    deviceInfo['device_model'] = androidInfo.model;
    deviceInfo['device_id'] = androidInfo.id;
    deviceInfo['serial_number'] = serialNumber;
    deviceInfo['imei'] = imei;
    deviceInfo['sector'] = sector;
    deviceInfo['floor'] = floor;
    deviceInfo['mac_address_radio'] = await networkInfo.getWifiBSSID() ?? 'N/A';
    deviceInfo['ip_address'] = await networkInfo.getWifiIP() ?? 'N/A';
    deviceInfo['network'] = await networkInfo.getWifiName() ?? 'N/A';
    deviceInfo['battery'] = batteryLevel;
    deviceInfo['last_seen'] = DateTime.now().toIso8601String();

    logger.info('Device info atualizado: $deviceInfo');
  }

  Future<bool> checkConnectivity() async {
    final connectivityResult = await connectivity.checkConnectivity();
    final isConnected = connectivityResult != ConnectivityResult.none;
    logger.info('Conectividade: $isConnected');
    return isConnected;
  }

  Future<bool> validateServerConnection(String host, String port) async {
    final httpClient = http.Client();
    try {
      logger.info('Validando servidor com authToken: $authToken');
      final response = await httpClient
          .get(
            Uri.parse('http://$host:$port/api/devices'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(const Duration(seconds: 5));
      logger.info('Validação do servidor: ${response.statusCode} ${response.body}');
      if (response.statusCode == 401) {
        logger.warning('Erro 401: Token não fornecido ou ausente');
      } else if (response.statusCode == 403) {
        logger.warning('Erro 403: Token inválido');
      }
      return response.statusCode == 200;
    } catch (e) {
      logger.severe('Erro ao validar conexão com o servidor: $e');
      return false;
    } finally {
      httpClient.close();
    }
  }

  Future<String> sendDeviceData() async {
    await initialize();
    logger.info('authToken: $authToken, serial_number: ${deviceInfo['serial_number']}');

    if (!await checkConnectivity() || deviceInfo['serial_number'] == null || authToken.isEmpty) {
      final message = 'Sem conexão, serial_number inválido (${deviceInfo['serial_number']}) ou token inválido ($authToken)';
      logger.severe('Erro: $message');
      return message;
    }

    final httpClient = http.Client();
    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        logger.info('Tentativa $attempts: Enviando para $serverUrl/api/devices/data');
        final response = await httpClient
            .post(
              Uri.parse('$serverUrl/api/devices/data'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $authToken',
              },
              body: jsonEncode(deviceInfo),
            )
            .timeout(timeout);

        logger.info('Resposta: ${response.statusCode} ${response.body}');
        if (response.statusCode == 200) {
          final prefs = await SharedPreferences.getInstance();
          final lastSync = DateTime.now().toIso8601String();
          await prefs.setString('last_sync', lastSync);
          deviceInfo['last_sync'] = lastSync;
          logger.info('Dados enviados com sucesso: ${response.body}');
          httpClient.close();
          return 'Dados enviados com sucesso';
        } else if (response.statusCode == 401) {
          logger.severe('Erro 401: Token inválido');
          httpClient.close();
          return 'Token inválido';
        } else if (response.statusCode == 403) {
          logger.severe('Erro 403: Acesso negado');
          httpClient.close();
          return 'Acesso negado';
        } else {
          logger.severe('Erro ${response.statusCode}: ${response.body}');
          httpClient.close();
          return 'Erro ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        logger.severe('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          httpClient.close();
          return 'Erro ao enviar dados: $e';
        }
        await Future.delayed(retryDelay);
      }
    }
    httpClient.close();
    return 'Falha após $maxRetries tentativas';
  }

  Future<String> sendHeartbeat() async {
    await initialize();
    logger.info('authToken: $authToken, serial_number: ${deviceInfo['serial_number']}');

    if (!await checkConnectivity() || serialnumber == null || authToken.isEmpty) {
      final message = 'Sem conexão ou token inválido';
      logger.severe('Erro: $message');
      return message;
    }

    final uri = Uri.parse(serverUrl);
    final host = uri.host;
    final port = uri.port.toString();
    if (!await validateServerConnection(host, port)) {
      final message = 'Servidor não acessível: $serverUrl';
      logger.severe('Erro: $message');
      return message;
    }

    final httpClient = http.Client();
    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        final response = await httpClient
            .post(
              Uri.parse('$serverUrl/api/devices/heartbeat'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $authToken',
              },
              body: jsonEncode({'device_id': deviceId}),
            )
            .timeout(timeout);

        logger.info('Heartbeat enviado: ${response.statusCode} ${response.body}');
        httpClient.close();
        return 'Heartbeat enviado com sucesso';
      } on TimeoutException {
        logger.warning('Tentativa $attempts: Timeout ao enviar heartbeat');
        if (attempts == maxRetries) {
          httpClient.close();
          return 'Falha: Timeout após $maxRetries tentativas';
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        logger.warning('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          httpClient.close();
          return 'Falha: Não foi possível conectar ao servidor ($e)';
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        logger.severe('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          httpClient.close();
          return 'Erro ao enviar heartbeat: $e';
        }
        await Future.delayed(retryDelay);
      }
    }
    httpClient.close();
    return 'Falha após $maxRetries tentativas';
  }

  Future<void> checkForCommands() async {
    if (!await checkConnectivity() || deviceInfo['serial_number'] == null || authToken.isEmpty) {
      logger.severe('Erro: Sem conexão, serial_number inválido ou token inválido');
      return;
    }

    final httpClient = http.Client();
    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        final response = await httpClient
            .get(
              Uri.parse('$serverUrl/api/devices/commands?serial_number=${deviceInfo['serial_number']}'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $authToken',
              },
            )
            .timeout(timeout);

        if (response.statusCode == 200) {
          final List<dynamic> commands = jsonDecode(response.body);
          for (var commandData in commands) {
            await executeCommand(
              commandData['command_type'],
              commandData['parameters'],
            );
          }
          logger.info('Comandos verificados: ${commands.length} comandos');
          httpClient.close();
          return;
        } else {
          logger.severe('Erro ${response.statusCode}: ${response.body}');
          httpClient.close();
          return;
        }
      } on TimeoutException {
        logger.warning('Tentativa $attempts: Timeout ao verificar comandos');
        if (attempts == maxRetries) {
          httpClient.close();
          return;
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        logger.warning('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          httpClient.close();
          return;
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        logger.severe('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          httpClient.close();
          return;
        }
        await Future.delayed(retryDelay);
      }
    }
    httpClient.close();
  }

  Future<void> applyServerPolicies() async {
    try {
      logger.info("Buscando políticas do servidor");
      final httpClient = http.Client();
      final response = await httpClient.get(
        Uri.parse('$serverUrl/api/devices/commands?serial_number=${deviceInfo['serial_number']}'),
        headers: {
          'Authorization': 'Bearer $authToken',
        },
      );
      httpClient.close();
      if (response.statusCode == 200) {
        final commands = jsonDecode(response.body);
        for (var cmd in commands) {
          await executeCommand(cmd['command_type'], cmd['parameters']);
        }
      } else {
        logger.warning("Falha ao buscar políticas: ${response.statusCode}");
      }
    } catch (e) {
      logger.severe("Erro ao aplicar políticas do servidor: $e");
    }
  }

  Future<void> executeCommand(String commandType, Map<String, dynamic> parameters) async {
    try {
      switch (commandType) {
        case "install_app":
          await platform.invokeMethod("installSystemApp", {"apkPath": parameters["apk_url"]});
          logger.info("Comando install_app executado: ${parameters['apk_url']}");
          break;
        case "restrict_settings":
          await platform.invokeMethod("restrictSettings", {"restrict": parameters["restrict"] ?? true});
          logger.info("Comando restrict_settings executado: ${parameters['restrict']}");
          break;
        case "lock_device":
          await platform.invokeMethod("lockDevice");
          logger.info("Comando lock_device executado");
          break;
        case "wipe_data":
          await platform.invokeMethod("wipeData");
          logger.info("Comando wipe_data executado");
          break;
        case "uninstall_package":
          await platform.invokeMethod("uninstallPackage", {"packageName": parameters["package_name"]});
          logger.info("Comando uninstall_package executado: ${parameters['package_name']}");
          break;
        default:
          logger.warning("Comando desconhecido: $commandType");
      }
    } catch (e) {
      logger.severe("Erro ao executar comando $commandType: $e");
    }
  }

  Future<void> installApp(String packageName, String apkUrl) async {
  try {
    final directory = await getTemporaryDirectory();
    final apkFile = File('${directory.path}/$packageName.apk');
    logger.info('Baixando APK de $apkUrl para ${apkFile.path}');
    final response = await http.get(Uri.parse(apkUrl));
    if (response.statusCode != 200) {
      throw Exception('Falha ao baixar APK: Status ${response.statusCode}');
    }
    await apkFile.writeAsBytes(response.bodyBytes);
    if (!await apkFile.exists()) {
      throw Exception('Falha ao salvar APK');
    }
    final result = await platform.invokeMethod('installSystemApp', {'apkPath': apkFile.path});
    logger.info('Resultado da instalação: $result');
  } catch (e) {
    logger.severe('Erro ao instalar aplicativo: $e');
    rethrow;
  }
}

  Future<void> uninstallApp(String packageName) async {
    try {
      await platform.invokeMethod('uninstallPackage', {'packageName': packageName});
      logger.info('Aplicativo $packageName desinstalado');
    } catch (e) {
      logger.severe('Erro ao desinstalar aplicativo: $e');
    }
  }

  Future<void> updateApp(String packageName, String apkUrl) async {
    try {
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/$packageName.apk');
      final response = await http.get(Uri.parse(apkUrl));
      await apkFile.writeAsBytes(response.bodyBytes);
      await platform.invokeMethod('installSystemApp', {'apkPath': apkFile.path});
      logger.info('Aplicativo $packageName atualizado');
    } catch (e) {
      logger.severe('Erro ao atualizar aplicativo: $e');
    }
  }

  Future<void> requestDeviceAdmin() async {
    try {
      await platform.invokeMethod('requestDeviceAdmin', {
        'explanation': 'MDM Client requer permissões de administrador para gerenciar o dispositivo.'
      });
    } catch (e) {
      logger.severe('Erro ao solicitar permissões de administrador: $e');
    }
  }

  Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}

class MDMClientHome extends StatefulWidget {
  const MDMClientHome({super.key});

  @override
  _MDMClientHomeState createState() => _MDMClientHomeState();
}

class _MDMClientHomeState extends State<MDMClientHome> {
  final DeviceService deviceService = DeviceService();
  String statusMessage = 'Iniciando...';
  String _connectionStatus = 'N/A';
  bool isConnected = false;
  bool isAdmin = false;
  int batteryLevel = 0;
  String lastSync = 'N/A';
  String lastHeartbeatError = '';
  int heartbeatFailureCount = 0;
  bool isServiceRunning = false;
  Timer? _timer; // Variável para armazenar o Timer
  final TextEditingController imeiController = TextEditingController();
  final TextEditingController serialController = TextEditingController();
  final TextEditingController sectorController = TextEditingController();
  final TextEditingController floorController = TextEditingController();
  final TextEditingController serverHostController = TextEditingController();
  final TextEditingController serverPortController = TextEditingController();
  final TextEditingController dataIntervalController = TextEditingController();
  final TextEditingController heartbeatIntervalController = TextEditingController();
  final TextEditingController commandCheckIntervalController = TextEditingController();
  final TextEditingController tokenController = TextEditingController();
  final NetworkInfo _networkInfo = NetworkInfo();

  @override
  void initState() {
    super.initState();
    _initializeClient();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return; // Verifica se o widget está montado
      final running = await deviceService.isServiceRunning();
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        isServiceRunning = running;
        lastHeartbeatError = prefs.getString('last_heartbeat_error') ?? '';
        heartbeatFailureCount = prefs.getInt('heartbeat_failure_count') ?? 0;
        if (!running) {
          statusMessage = 'Serviço em segundo plano parado. Reinicie o app.';
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancela o Timer
    imeiController.dispose();
    serialController.dispose();
    sectorController.dispose();
    floorController.dispose();
    serverHostController.dispose();
    serverPortController.dispose();
    dataIntervalController.dispose();
    heartbeatIntervalController.dispose();
    commandCheckIntervalController.dispose();
    tokenController.dispose();
    super.dispose();
  }


  Future<void> _initNetworkInfo() async {
    String? wifiName, wifiBSSID, wifiIPv4, wifiIPv6, wifiGatewayIP, wifiBroadcast, wifiSubmask;

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        if (await Permission.locationWhenInUse.request().isGranted) {
          wifiName = await _networkInfo.getWifiName();
        } else {
          wifiName = 'Unauthorized to get Wifi Name';
        }
      } else {
        wifiName = await _networkInfo.getWifiName();
      }
    } on PlatformException catch (e) {
      deviceService.logger.severe('Failed to get Wifi Name: $e');
      wifiName = 'Failed to get Wifi Name';
    }

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        if (await Permission.locationWhenInUse.request().isGranted) {
          wifiBSSID = await _networkInfo.getWifiBSSID();
        } else {
          wifiBSSID = 'Unauthorized to get Wifi BSSID';
        }
      } else {
        wifiBSSID = await _networkInfo.getWifiBSSID();
      }
    } on PlatformException catch (e) {
      deviceService.logger.severe('Failed to get Wifi BSSID: $e');
      wifiBSSID = 'Failed to get Wifi BSSID';
    }

    try {
      wifiIPv4 = await _networkInfo.getWifiIP();
    } on PlatformException catch (e) {
      deviceService.logger.severe('Failed to get Wifi IPv4: $e');
      wifiIPv4 = 'Failed to get Wifi IPv4';
    }

    try {
      wifiIPv6 = await _networkInfo.getWifiIPv6();
    } on PlatformException catch (e) {
      deviceService.logger.severe('Failed to get Wifi IPv6: $e');
      wifiIPv6 = 'Failed to get Wifi IPv6';
    }

    try {
      wifiSubmask = await _networkInfo.getWifiSubmask();
    } on PlatformException catch (e) {
      deviceService.logger.severe('Failed to get Wifi submask address: $e');
      wifiSubmask = 'Failed to get Wifi submask address';
    }

    try {
      wifiBroadcast = await _networkInfo.getWifiBroadcast();
    } on PlatformException catch (e) {
      deviceService.logger.severe('Failed to get Wifi broadcast: $e');
      wifiBroadcast = 'Failed to get Wifi broadcast';
    }

    try {
      wifiGatewayIP = await _networkInfo.getWifiGatewayIP();
    } on PlatformException catch (e) {
      deviceService.logger.severe('Failed to get Wifi gateway address: $e');
      wifiGatewayIP = 'Failed to get Wifi gateway address';
    }

    if (!mounted) return;
    setState(() {
      _connectionStatus = 'Wifi Name: $wifiName\n'
          'Wifi BSSID: $wifiBSSID\n'
          'Wifi IPv4: $wifiIPv4\n'
          'Wifi IPv6: $wifiIPv6\n'
          'Wifi Broadcast: $wifiBroadcast\n'
          'Wifi Gateway: $wifiGatewayIP\n'
          'Wifi Submask: $wifiSubmask\n';
    });
  }

  Future<void> _initializeClient() async {
    if (!mounted) return;
    setState(() {
      statusMessage = 'Inicializando...';
    });

    final prefs = await SharedPreferences.getInstance();
    final imei = prefs.getString('imei') ?? '';
    final serial = prefs.getString('serial_number') ?? '';
    final sector = prefs.getString('sector') ?? '';
    final floor = prefs.getString('floor') ?? '';
    final serverHost = prefs.getString('server_host') ?? '192.168.0.183';
    final serverPort = prefs.getString('server_port') ?? '3000';
    final dataInterval = prefs.getInt('data_interval') ?? 10;
    final heartbeatInterval = prefs.getInt('heartbeat_interval') ?? 3;
    final commandCheckInterval = prefs.getInt('command_check_interval') ?? 1;
    final token = prefs.getString('auth_token') ?? '';
    final lastSync = prefs.getString('last_sync') ?? 'N/A';
    final lastHeartbeatError = prefs.getString('last_heartbeat_error') ?? '';
    final heartbeatFailureCount = prefs.getInt('heartbeat_failure_count') ?? 0;

    if (!mounted) return;
    setState(() {
      imeiController.text = imei;
      serialController.text = serial;
      sectorController.text = sector;
      floorController.text = floor;
      serverHostController.text = serverHost;
      serverPortController.text = serverPort;
      dataIntervalController.text = dataInterval.toString();
      heartbeatIntervalController.text = heartbeatInterval.toString();
      commandCheckIntervalController.text = commandCheckInterval.toString();
      tokenController.text = token;
      this.lastSync = lastSync;
      this.lastHeartbeatError = lastHeartbeatError;
      this.heartbeatFailureCount = heartbeatFailureCount;
    });

    await deviceService.initialize();
    await _initNetworkInfo();

    final connectivityResult = await deviceService.checkConnectivity();
    if (!mounted) return;
    setState(() {
      isConnected = connectivityResult;
      statusMessage = isConnected ? 'Conectado à rede' : 'Sem conexão';
    });

    final batteryLevel = await deviceService.battery.batteryLevel;
    if (!mounted) return;
    setState(() {
      this.batteryLevel = batteryLevel;
    });

    bool isAdminActive = false;
    try {
      isAdminActive = await DeviceService.platform.invokeMethod('isDeviceOwnerOrProfileOwner');
      if (!isAdminActive) {
        await deviceService.requestDeviceAdmin();
      }
    } on PlatformException catch (e) {
      deviceService.logger.severe('Erro ao verificar permissões de administrador: $e');
      if (e.code == 'MissingPluginException') {
        deviceService.logger.severe('MethodChannel não encontrado. Verifique a integração com MainActivity.kt');
        if (!mounted) return;
        setState(() {
          statusMessage = 'Erro: Integração nativa ausente. Reinstale o aplicativo.';
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      isAdmin = isAdminActive;
      statusMessage = isAdmin ? 'Permissões de administrador concedidas' : 'Permissões de administrador necessárias';
    });

    isServiceRunning = await deviceService.isServiceRunning();
    if (!isServiceRunning) {
      final service = FlutterBackgroundService();
      await service.startService();
      if (!mounted) return;
      setState(() {
        isServiceRunning = true;
        statusMessage = 'Serviço em segundo plano iniciado';
      });
    }

    if (isConnected && deviceService.deviceId != null && deviceService.authToken.isNotEmpty) {
      final result = await deviceService.sendDeviceData();
      if (!mounted) return;
      setState(() {
        statusMessage = result;
      });
      await deviceService.sendHeartbeat();
      await deviceService.checkForCommands();
    } else if (deviceService.authToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        statusMessage = 'Por favor, insira um token de autenticação';
      });
    }
  }

  Future<void> _saveManualData() async {
    final prefs = await SharedPreferences.getInstance();
    final imei = imeiController.text.trim();
    final serial = serialController.text.trim();
    final sector = sectorController.text.trim();
    final floor = floorController.text.trim();
    final serverHost = serverHostController.text.trim();
    final serverPort = serverPortController.text.trim();
    final dataInterval = int.tryParse(dataIntervalController.text.trim()) ?? 10;
    final heartbeatInterval = int.tryParse(heartbeatIntervalController.text.trim()) ?? 3;
    final commandCheckInterval = int.tryParse(commandCheckIntervalController.text.trim()) ?? 1;
    final token = tokenController.text.trim();

    if (imei.isEmpty || serial.isEmpty || sector.isEmpty || floor.isEmpty || serverHost.isEmpty || serverPort.isEmpty || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        statusMessage = 'Todos os campos são obrigatórios';
      });
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(serverPort)) {
      if (!mounted) return;
      setState(() {
        statusMessage = 'A porta deve ser um número';
      });
      return;
    }

    final testClient = http.Client();
    try {
      final response = await testClient.get(
        Uri.parse('http://$serverHost:$serverPort/api/devices'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          statusMessage = 'Token inválido: Erro ${response.statusCode}';
        });
        testClient.close();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        statusMessage = 'Não foi possível validar o token: $e';
      });
      testClient.close();
      return;
    } finally {
      testClient.close();
    }

    await prefs.setString('imei', imei);
    await prefs.setString('serial_number', serial);
    await prefs.setString('sector', sector);
    await prefs.setString('floor', floor);
    await prefs.setString('server_host', serverHost);
    await prefs.setString('server_port', serverPort);
    await prefs.setInt('data_interval', dataInterval);
    await prefs.setInt('heartbeat_interval', heartbeatInterval);
    await prefs.setInt('command_check_interval', commandCheckInterval);
    await prefs.setString('auth_token', token);

    deviceService.deviceInfo['imei'] = imei;
    deviceService.deviceInfo['serial_number'] = serial;
    deviceService.deviceInfo['sector'] = sector;
    deviceService.deviceInfo['floor'] = floor;
    deviceService.serverUrl = 'http://$serverHost:$serverPort';
    deviceService.authToken = token;

    if (!mounted) return;
    setState(() {
      statusMessage = 'Dados salvos com sucesso';
    });

    final result = await deviceService.sendDeviceData();
    if (!mounted) return;
    setState(() {
      statusMessage = result;
    });

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
    }
    await service.startService();
    if (!mounted) return;
    setState(() {
      isServiceRunning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lastSyncFormatted = lastSync != 'N/A'
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(lastSync))
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text('MDM Client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeClient,
            tooltip: 'Recarregar Dados',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status do Sistema',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            isConnected ? Icons.wifi : Icons.wifi_off,
                            color: isConnected ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Status: $statusMessage',
                              style: TextStyle(
                                fontSize: 16,
                                color: isConnected ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            isServiceRunning ? Icons.check_circle : Icons.error,
                            color: isServiceRunning ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Serviço: ${isServiceRunning ? 'Ativo' : 'Inativo'}',
                            style: TextStyle(
                              fontSize: 16,
                              color: isServiceRunning ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (lastHeartbeatError.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Última falha de heartbeat: $lastHeartbeatError',
                          style: const TextStyle(fontSize: 14, color: Colors.red),
                        ),
                      ],
                      if (heartbeatFailureCount > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Falhas consecutivas: $heartbeatFailureCount',
                          style: const TextStyle(fontSize: 14, color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        _connectionStatus,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Device Info Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Informações do Dispositivo',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text('Nome: ${deviceService.deviceInfo['device_name'] ?? 'N/A'}'),
                      Text('Modelo: ${deviceService.deviceInfo['device_model'] ?? 'N/A'}'),
                      Text('ID: ${deviceService.deviceInfo['device_id'] ?? 'N/A'}'),
                      Text('Bateria: $batteryLevel%'),
                      Text('Administrador: ${isAdmin ? 'Ativo' : 'Inativo'}'),
                      Text('Última Sincronização: $lastSyncFormatted'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Configuration Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configurações Manuais',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: imeiController,
                        decoration: InputDecoration(
                          labelText: 'IMEI',
                          prefixIcon: const Icon(Icons.perm_device_information),
                          errorText: imeiController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serialController,
                        decoration: InputDecoration(
                          labelText: 'Número de Série',
                          prefixIcon: const Icon(Icons.confirmation_number),
                          errorText: serialController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sectorController,
                        decoration: InputDecoration(
                          labelText: 'Setor',
                          prefixIcon: const Icon(Icons.business),
                          errorText: sectorController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: floorController,
                        decoration: InputDecoration(
                          labelText: 'Andar',
                          prefixIcon: const Icon(Icons.stairs),
                          errorText: floorController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serverHostController,
                        decoration: InputDecoration(
                          labelText: 'Host do Servidor',
                          prefixIcon: const Icon(Icons.dns),
                          errorText: serverHostController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serverPortController,
                        decoration: InputDecoration(
                          labelText: 'Porta do Servidor',
                          prefixIcon: const Icon(Icons.network_check),
                          errorText: serverPortController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dataIntervalController,
                        decoration: InputDecoration(
                          labelText: 'Intervalo de Dados (minutos)',
                          prefixIcon: const Icon(Icons.timer),
                          errorText: dataIntervalController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: heartbeatIntervalController,
                        decoration: InputDecoration(
                          labelText: 'Intervalo de Heartbeat (minutos)',
                          prefixIcon: const Icon(Icons.favorite),
                          errorText: heartbeatIntervalController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commandCheckIntervalController,
                        decoration: InputDecoration(
                          labelText: 'Intervalo de Verificação de Comandos (minutos)',
                          prefixIcon: const Icon(Icons.checklist),
                          errorText: commandCheckIntervalController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenController,
                        decoration: InputDecoration(
                          labelText: 'Token de Autenticação',
                          prefixIcon: const Icon(Icons.vpn_key),
                          errorText: tokenController.text.isEmpty ? 'Campo obrigatório' : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Salvar Dados'),
                        onPressed: _saveManualData,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar Dados'),
                        onPressed: () async {
                          final result = await deviceService.sendDeviceData();
                          if (!mounted) return;
                          setState(() {
                            statusMessage = result;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Verificar/Reiniciar Serviço'),
                  onPressed: () async {
                    final running = await deviceService.isServiceRunning();
                    if (!running) {
                      final service = FlutterBackgroundService();
                      await service.startService();
                      if (!mounted) return;
                      setState(() {
                        isServiceRunning = true;
                        statusMessage = 'Serviço em segundo plano reiniciado';
                      });
                    } else {
                      if (!mounted) return;
                      setState(() {
                        statusMessage = 'Serviço em segundo plano já está ativo';
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 24),
              // Developer Info
              Center(
                child: Text(
                  'Desenvolvido por: Alexandre Calmon TI-BA\nVersão: 1.0.0\nalexandre.calmon@hapvida.com.br',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
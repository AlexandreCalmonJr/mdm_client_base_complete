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
import 'package:logger/logger.dart';
import 'package:network_info_plus/network_info_plus.dart'; // Added for network info
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';




void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MDMClientApp());
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
  final logger = Logger();
  
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

  logger.i('Serviço em segundo plano iniciado: ${DateTime.now()}');
  logger.i('Intervalos configurados: Data: $dataInterval min, Heartbeat: $heartbeatInterval min, Comandos: $commandCheckInterval min');
  int heartbeatFailureCount = prefs.getInt('heartbeat_failure_count') ?? 0;
  Timer.periodic(const Duration(minutes: 1), (_) async {
    final now = DateTime.now();
    final minutesSinceStart = now.difference(DateTime(now.year, now.month, now.day)).inMinutes;

    if (minutesSinceStart % dataInterval == 0) {
      final result = await deviceService.sendDeviceData();
      logger.i('Dados enviados: $result');
    }

    if (minutesSinceStart % heartbeatInterval == 0) {
      final result = await deviceService.sendHeartbeat();
      logger.i('Heartbeat: $result${heartbeatFailureCount > 0 ? ', Falhas: $heartbeatFailureCount' : ''}');
      if (result != 'Heartbeat enviado com sucesso') {
        heartbeatFailureCount++;
        await prefs.setString('last_heartbeat_error', '$result às ${DateTime.now().toIso8601String()}');
        await prefs.setInt('heartbeat_failure_count', heartbeatFailureCount);
      } else {
        heartbeatFailureCount = 0;
        await prefs.remove('last_heartbeat_error');
        await prefs.setInt('heartbeat_failure_count', heartbeatFailureCount);
      }
    }

    if (minutesSinceStart % commandCheckInterval == 0) {
      await deviceService.checkForCommands();
    }

    if (service is AndroidServiceInstance && !await service.isForegroundService()) {
      logger.w('Serviço parou inesperadamente. Tentando reiniciar...');
      await FlutterBackgroundService().startService();
    }
  });
}

class MDMClientApp extends StatelessWidget {
  const MDMClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Client',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 8),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.teal),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.teal, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.teal),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          bodySmall: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ),
      home: const MDMClientHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DeviceService {
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');
  String serverUrl = 'http://192.168.0.183:3000';
  String authToken = '';
  final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final Battery battery = Battery();
  final Connectivity connectivity = Connectivity();
  final NetworkInfo networkInfo = NetworkInfo(); // d: use NetworkInfo from network_info_plusFixe
  final Logger logger = Logger();
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
    final imei = prefs.getString('imei') ?? androidInfo.serialNumber ?? 'N/A';
    final serialNumber = prefs.getString('serial_number') ?? androidInfo.serialNumber ?? 'N/A';
    final sector = prefs.getString('sector') ?? 'N/A';
    final floor = prefs.getString('floor') ?? 'N/A';
    final serverHost = prefs.getString('server_host') ?? '192.168.0.183';
    final serverPort = prefs.getString('server_port') ?? '3000';
    final lastSync = prefs.getString('last_sync') ?? 'N/A';
    authToken = prefs.getString('auth_token') ?? 'seu_token_aqui'; // Usar token correto
    await prefs.setString('auth_token', authToken);
    logger.i('authToken configurado: $authToken, serial_number: $serialNumber');
    final batteryLevel = await battery.batteryLevel; // Forçar token correto
    logger.i('authToken forçado: $authToken');

    await prefs.setString('auth_token', authToken);
    
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
    logger.i('Inicializado: serverUrl=$serverUrl, deviceId=$deviceId');
  }

Future<void> _refreshMacAddress() async {
  try {
    if (await Permission.locationWhenInUse.request().isGranted) {
      final newMac = await networkInfo.getWifiBSSID() ?? await _getRealMacAddress();
      if (_isValidMacAddress(newMac)) {
        deviceInfo['mac_address_radio'] = newMac;
        logger.i('MAC address atualizado: $newMac');
      } else {
        logger.w('MAC address inválido obtido: $newMac');
        deviceInfo['mac_address_radio'] = 'N/A';
      }
    } else {
      logger.w('Permissão de localização negada');
      deviceInfo['mac_address_radio'] = 'Permissão negada';
    }
  } catch (e) {
    logger.e('Erro ao atualizar MAC address: $e');
    deviceInfo['mac_address_radio'] = 'Error';
  }
}
Future<String> _getRealMacAddress() async {
  if (kIsWeb) {
    return 'N/A';
  } else {
    try {
      // Verificar permissão ACCESS_WIFI_STATE
      if (await Permission.location.request().isGranted) {
        final macAddress = await _invokeMethodChannel('getMacAddress');
        return macAddress ?? 'N/A';
      } else {
        logger.e('Permissão ACCESS_WIFI_STATE negada');
        return 'Permissão negada';
      }
    } catch (e) {
      logger.e('Erro ao obter MAC address: $e');
      return 'Error';
    }
  }
}

Future<String?> _invokeMethodChannel(String method, [Map<String, dynamic>? arguments]) async {
  const platform = MethodChannel('com.example.mdm_client_base/device_policy');
  try {
    final result = await platform.invokeMethod<String>(method, arguments);
    return result;
  } on PlatformException catch (e) {
    logger.e('Erro ao invocar método $method: ${e.message}');
    rethrow;
  }
}
bool _isValidMacAddress(String? mac) {
  if (mac == null || mac.isEmpty || mac == 'null') return false;
  
  // Verificar se o MAC address não é um valor conhecido como "fake"
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
    logger.i('serverUrl atualizado: $serverUrl');
  }
  Future<void> setAuthToken(String token) async {
    authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', authToken);
    logger.i('authToken atualizado: $authToken');
  }
  Future<void> updateDeviceInfo() async {
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final prefs = await SharedPreferences.getInstance();
    final imei = prefs.getString('imei') ?? androidInfo.serialNumber ?? 'N/A';
    final serialNumber = prefs.getString('serial_number') ?? androidInfo.serialNumber ?? 'N/A';
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
    deviceInfo['mac_address_radio'] = bssid;
    deviceInfo['ip_address'] = await networkInfo.getWifiIP() ?? 'N/A';
    deviceInfo['network'] = await networkInfo.getWifiName() ?? 'N/A';
    deviceInfo['battery'] = batteryLevel;
    deviceInfo['last_seen'] = DateTime.now().toIso8601String();
    
    logger.i('Device info atualizado: $deviceInfo');
  }
  Future<bool> checkConnectivity() async {
    final connectivityResult = await connectivity.checkConnectivity();
    // ignore: unrelated_type_equality_checks
    final isConnected = connectivityResult != ConnectivityResult.none;
    logger.i('Conectividade: $isConnected');
    return isConnected;
  }
  Future<bool> validateServerConnection(String host, String port) async {
 final httpClient = http.Client();
  try {
    logger.i('Validando servidor com authToken: $authToken');
    final response = await httpClient
        .get(
          Uri.parse('http://$host:$port/api/devices'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $authToken',
          },
        )
        .timeout(const Duration(seconds: 5));
    logger.i('Validação do servidor: ${response.statusCode} ${response.body}');
    if (response.statusCode == 401) {
      logger.w('Erro 401: Token não fornecido ou ausente');
    } else if (response.statusCode == 403) {
      logger.w('Erro 403: Token inválido');
    }
    return response.statusCode == 200;
  } catch (e) {
    logger.e('Erro ao validar conexão com o servidor: $e');
    return false;
  } finally {
    httpClient.close();
  }
}
  Future<String> sendDeviceData() async {
  await initialize();
  logger.i('authToken: $authToken, serial_number: ${deviceInfo['serial_number']}');

  if (!await checkConnectivity() || deviceInfo['serial_number'] == null || authToken.isEmpty) {
    final message = 'Sem conexão, serial_number inválido (${deviceInfo['serial_number']}) ou token inválido ($authToken)';
    logger.e('Erro: $message');
    return message;
  }

  final httpClient = http.Client();
  int attempts = 0;
  while (attempts < maxRetries) {
    attempts++;
    try {
      logger.i('Tentativa $attempts: Enviando para $serverUrl/api/devices/data');
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

      logger.i('Resposta: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        final lastSync = DateTime.now().toIso8601String();
        await prefs.setString('last_sync', lastSync);
        deviceInfo['last_sync'] = lastSync;
        logger.i('Dados enviados com sucesso: ${response.body}');
        httpClient.close();
        return 'Dados enviados com sucesso';
      } else if (response.statusCode == 401) {
        logger.e('Erro 401: Token inválido');
        httpClient.close();
        return 'Token inválido';
      } else if (response.statusCode == 403) {
        logger.e('Erro 403: Acesso negado');
        httpClient.close();
        return 'Acesso negado';
      } else {
        logger.e('Erro ${response.statusCode}: ${response.body}');
        httpClient.close();
        return 'Erro ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      logger.e('Tentativa $attempts: Erro inesperado: $e');
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
    logger.i('authToken: $authToken, serial_number: ${deviceInfo['serial_number']}');

    if (!await checkConnectivity() || serialnumber == null || authToken.isEmpty) {
      final message = 'Sem conexão ou token inválido';
      logger.e('Erro: $message');
      return message;
    }

    final uri = Uri.parse(serverUrl);
    final host = uri.host;
    final port = uri.port.toString();
    if (!await validateServerConnection(host, port)) {
      final message = 'Servidor não acessível: $serverUrl';
      logger.e('Erro: $message');
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

        logger.i('Heartbeat enviado: ${response.statusCode} ${response.body}');
        httpClient.close();
        return 'Heartbeat enviado com sucesso';
      } on TimeoutException {
        logger.w('Tentativa $attempts: Timeout ao enviar heartbeat');
        if (attempts == maxRetries) {
          httpClient.close();
          return 'Falha: Timeout após $maxRetries tentativas';
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        logger.w('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          httpClient.close();
          return 'Falha: Não foi possível conectar ao servidor ($e)';
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        logger.e('Tentativa $attempts: Erro inesperado: $e');
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
    logger.e('Erro: Sem conexão, serial_number inválido ou token inválido');
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
            commandData['parameters']?['packageName'],
            commandData['parameters']?['apkUrl'],
          );
        }
        logger.i('Comandos verificados: ${commands.length} comandos');
        httpClient.close();
        return;
      } else {
        logger.e('Erro ${response.statusCode}: ${response.body}');
        httpClient.close();
        return;
      }
    } on TimeoutException {
      logger.w('Tentativa $attempts: Timeout ao verificar comandos');
      if (attempts == maxRetries) {
        httpClient.close();
        return;
      }
      await Future.delayed(retryDelay);
    } on SocketException catch (e) {
      logger.w('Tentativa $attempts: SocketException: $e');
      if (attempts == maxRetries) {
        httpClient.close();
        return;
      }
      await Future.delayed(retryDelay);
    } catch (e) {
      logger.e('Tentativa $attempts: Erro inesperado: $e');
      if (attempts == maxRetries) {
        httpClient.close();
        return;
      }
      await Future.delayed(retryDelay);
    }
  }
  httpClient.close();
}
  Future<void> executeCommand(String command, String? packageName, String? apkUrl) async {
    bool isAdmin;
    try {
      isAdmin = await platform.invokeMethod('isDeviceOwnerOrProfileOwner');
    } on PlatformException catch (e) {
      logger.e('Erro ao verificar permissões de administrador: $e');
      if (e.code == 'MissingPluginException') {
        logger.e('MethodChannel não encontrado. Verifique a integração com MainActivity.kt');
      }
      return;
    }

    if (!isAdmin) {
      logger.w('Permissões de administrador necessárias');
      return;
    }

    try {
      switch (command) {
        case 'lock':
          await platform.invokeMethod('lockDevice');
          logger.i('Dispositivo bloqueado');
          break;
        case 'wipe':
          await platform.invokeMethod('wipeData');
          logger.i('Dados apagados');
          break;
        case 'install_app':
          if (packageName != null && apkUrl != null) {
            await installApp(packageName, apkUrl);
          }
          break;
        case 'uninstall_app':
          if (packageName != null) {
            await uninstallApp(packageName);
          }
          break;
        case 'update_app':
          if (packageName != null && apkUrl != null) {
            await updateApp(packageName, apkUrl);
          }
          break;
        default:
          logger.w('Comando desconhecido: $command');
      }
    } catch (e) {
      logger.e('Erro ao executar comando: $e');
    }
  }
  Future<void> installApp(String packageName, String apkUrl) async {
    try {
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/$packageName.apk');
      final response = await http.get(Uri.parse(apkUrl));
      await apkFile.writeAsBytes(response.bodyBytes);
      await platform.invokeMethod('installSystemApp', {'apkPath': apkFile.path});
      logger.i('Aplicativo $packageName instalado');
    } catch (e) {
      logger.e('Erro ao instalar aplicativo: $e');
    }
  }
  Future<void> uninstallApp(String packageName) async {
    try {
      await platform.invokeMethod('uninstallPackage', {'packageName': packageName});
      logger.i('Aplicativo $packageName desinstalado');
    } catch (e) {
      logger.e('Erro ao desinstalar aplicativo: $e');
    }
  }
  Future<void> updateApp(String packageName, String apkUrl) async {
    try {
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/$packageName.apk');
      final response = await http.get(Uri.parse(apkUrl));
      await apkFile.writeAsBytes(response.bodyBytes);
      await platform.invokeMethod('installSystemApp', {'apkPath': apkFile.path});
      logger.i('Aplicativo $packageName atualizado');
    } catch (e) {
      logger.e('Erro ao atualizar aplicativo: $e');
    }
  }
  Future<void> requestDeviceAdmin() async {
    try {
      await platform.invokeMethod('requestDeviceAdmin', {
        'explanation': 'MDM Client requer permissões de administrador para gerenciar o dispositivo.'
      });
    } catch (e) {
      logger.e('Erro ao solicitar permissões de administrador: $e');
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
  String _connectionStatus = 'N/A'; // Added for network info
  bool isConnected = false;
  bool isAdmin = false;
  int batteryLevel = 0;
  String lastSync = 'N/A';
  String lastHeartbeatError = '';
  int heartbeatFailureCount = 0;
  bool isServiceRunning = false;
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
  final NetworkInfo _networkInfo = NetworkInfo(); // Fixed: use NetworkInfo from network_info_plus

  @override
  void initState() {
    super.initState();
    _initializeClient();
    Timer.periodic(const Duration(seconds: 30), (_) async {
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

  Future<void> _initNetworkInfo() async {
    String? wifiName,
        wifiBSSID,
        wifiIPv4,
        wifiIPv6,
        wifiGatewayIP,
        wifiBroadcast,
        wifiSubmask;

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
      deviceService.logger.e('Failed to get Wifi Name: $e'); // Replaced developer.log
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
        wifiBSSID = await _networkInfo.getWifiBSSID(); // Fixed duplicate wifiName
      }
    } on PlatformException catch (e) {
      deviceService.logger.e('Failed to get Wifi BSSID: $e'); // Replaced developer.log
      wifiBSSID = 'Failed to get Wifi BSSID';
    }

    try {
      wifiIPv4 = await _networkInfo.getWifiIP();
    } on PlatformException catch (e) {
      deviceService.logger.e('Failed to get Wifi IPv4: $e'); // Replaced developer.log
      wifiIPv4 = 'Failed to get Wifi IPv4';
    }

    try {
      wifiIPv6 = await _networkInfo.getWifiIPv6();
    } on PlatformException catch (e) {
      deviceService.logger.e('Failed to get Wifi IPv6: $e'); // Replaced developer.log
      wifiIPv6 = 'Failed to get Wifi IPv6';
    }

    try {
      wifiSubmask = await _networkInfo.getWifiSubmask();
    } on PlatformException catch (e) {
      deviceService.logger.e('Failed to get Wifi submask address: $e'); // Replaced developer.log
      wifiSubmask = 'Failed to get Wifi submask address';
    }

    try {
      wifiBroadcast = await _networkInfo.getWifiBroadcast();
    } on PlatformException catch (e) {
      deviceService.logger.e('Failed to get Wifi broadcast: $e'); // Replaced developer.log
      wifiBroadcast = 'Failed to get Wifi broadcast';
    }

    try {
      wifiGatewayIP = await _networkInfo.getWifiGatewayIP();
    } on PlatformException catch (e) {
      deviceService.logger.e('Failed to get Wifi gateway address: $e'); // Replaced developer.log
      wifiGatewayIP = 'Failed to get Wifi gateway address';
    }

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
    await _initNetworkInfo(); // Moved here to ensure context

    final connectivityResult = await deviceService.checkConnectivity();
    setState(() {
      isConnected = connectivityResult;
      statusMessage = isConnected ? 'Conectado à rede' : 'Sem conexão';
    });

    final batteryLevel = await deviceService.battery.batteryLevel;
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
      deviceService.logger.e('Erro ao verificar permissões de administrador: $e');
      if (e.code == 'MissingPluginException') {
        deviceService.logger.e('MethodChannel não encontrado. Verifique a integração com MainActivity.kt');
        setState(() {
          statusMessage = 'Erro: Integração nativa ausente. Reinstale o aplicativo.';
        });
        return;
      }
    }

    setState(() {
      isAdmin = isAdminActive;
      statusMessage = isAdmin ? 'Permissões de administrador concedidas' : 'Permissões de administrador necessárias';
    });

    isServiceRunning = await deviceService.isServiceRunning();
    if (!isServiceRunning) {
      final service = FlutterBackgroundService();
      await service.startService();
      setState(() {
        isServiceRunning = true;
        statusMessage = 'Serviço em segundo plano iniciado';
      });
    }

    if (isConnected && deviceService.deviceId != null && deviceService.authToken.isNotEmpty) {
      final result = await deviceService.sendDeviceData();
      setState(() {
        statusMessage = result;
      });
      await deviceService.sendHeartbeat();
      await deviceService.checkForCommands();
    } else if (deviceService.authToken.isEmpty) {
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
    setState(() {
      statusMessage = 'Todos os campos são obrigatórios';
    });
    return;
  }
  if (!RegExp(r'^\d+$').hasMatch(serverPort)) {
    setState(() {
      statusMessage = 'A porta deve ser um número';
    });
    return;
  }

  // Testar token antes de salvar
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
      setState(() {
        statusMessage = 'Token inválido: Erro ${response.statusCode}';
      });
      testClient.close();
      return;
    }
  } catch (e) {
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

  setState(() {
    statusMessage = 'Dados salvos com sucesso';
  });

  final result = await deviceService.sendDeviceData();
  setState(() {
    statusMessage = result;
  });

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('stopService');
  }
  await service.startService();
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
                        _connectionStatus, // Added network info display
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
                      setState(() {
                        isServiceRunning = true;
                        statusMessage = 'Serviço em segundo plano reiniciado';
                      });
                    } else {
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
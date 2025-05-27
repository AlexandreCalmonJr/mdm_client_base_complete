import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';

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
    // Aguardar um pouco antes de configurar os listeners
    await Future.delayed(const Duration(milliseconds: 1000));
    
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
  await deviceService.initialize();
  final prefs = await SharedPreferences.getInstance();
  final dataInterval = prefs.getInt('data_interval') ?? 10;
  final heartbeatInterval = prefs.getInt('heartbeat_interval') ?? 3;
  final commandCheckInterval = prefs.getInt('command_check_interval') ?? 1;

  logger.i('Serviço em segundo plano iniciado: ${DateTime.now()}');

  int heartbeatFailureCount = prefs.getInt('heartbeat_failure_count') ?? 0;
  Timer.periodic(const Duration(minutes: 1), (_) async {
    final now = DateTime.now();
    final minutesSinceStart =
        now.difference(DateTime(now.year, now.month, now.day)).inMinutes;

    if (minutesSinceStart % dataInterval == 0) {
      final result = await deviceService.sendDeviceData();
      logger.i('Dados enviados: $result');
    }

    if (minutesSinceStart % heartbeatInterval == 0) {
      final result = await deviceService.sendHeartbeat();
      logger.i(
        'Heartbeat: $result${heartbeatFailureCount > 0 ? ', Falhas: $heartbeatFailureCount' : ''}',
      );
      if (result != 'Heartbeat enviado com sucesso') {
        heartbeatFailureCount++;
        await prefs.setString(
          'last_heartbeat_error',
          '$result às ${DateTime.now().toIso8601String()}',
        );
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

    if (service is AndroidServiceInstance &&
        !await service.isForegroundService()) {
      logger.w('Serviço parou inesperadamente. Tentando reiniciar...');
      await FlutterBackgroundService().startService();
    }
  });
}

class QRCodeScannerScreen extends StatefulWidget {
  const QRCodeScannerScreen({super.key});

  @override
  _QRCodeScannerScreenState createState() => _QRCodeScannerScreenState();
}

class _QRCodeScannerScreenState extends State<QRCodeScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  String scannedUrl = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR Code'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    setState(() {
                      scannedUrl = barcode.rawValue!;
                    });
                    Navigator.pop(context, scannedUrl);
                  }
                }
              },
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                scannedUrl.isEmpty ? 'Escaneie o QR Code' : 'URL: $scannedUrl',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          bodySmall: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController passwordController = TextEditingController();
  String errorMessage = '';

  Future<void> _login() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPassword = prefs.getString('app_password') ?? 'hap@2025';

    if (passwordController.text == storedPassword) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MDMClientHome()),
      );
    } else {
      setState(() {
        errorMessage = 'Senha incorreta';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MDM Client - Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Digite a senha para acessar o MDM Client',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock),
                errorText: errorMessage.isNotEmpty ? errorMessage : null,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _login, child: const Text('Entrar')),
          ],
        ),
      ),
    );
  }
}

class DeviceService {
  static const platform = MethodChannel(
    'com.example.mdm_client_base/device_policy',
  );
  String serverUrl = 'http://192.168.0.183:3000';
  String authToken = '';
  final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final Battery battery = Battery();
  final Connectivity connectivity = Connectivity();
  final Logger logger = Logger();
  String? deviceId;
  Map<String, dynamic> deviceInfo = {};
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration timeout = Duration(seconds: 10);

  /// Disable unwanted apps by their package names.
  Future<String> disableUnwantedApps(List<String> packageNames) async {
    try {
      final isAdmin = await platform.invokeMethod('isDeviceOwnerOrProfileOwner');
      if (!isAdmin) {
        logger.w('Permissões de administrador necessárias para desabilitar aplicativos');
        await requestDeviceAdmin();
        return 'Permissões de administrador necessárias';
      }
      for (final packageName in packageNames) {
        await platform.invokeMethod('disablePackage', {'packageName': packageName});
        logger.i('Aplicativo $packageName desabilitado');
      }
      return 'Aplicativos desabilitados com sucesso';
    } catch (e) {
      logger.e('Erro ao desabilitar aplicativos: $e');
      return 'Erro ao desabilitar aplicativos: $e';
    }
  }

  /// Checks if the device has an active network connection.
  Future<bool> checkConnectivity() async {
    var connectivityResult = await connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> initialize() async {
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final prefs = await SharedPreferences.getInstance();
    final imei = prefs.getString('imei') ?? androidInfo.serialNumber ?? 'N/A';
    final serialNumber =
        prefs.getString('serial_number') ?? androidInfo.serialNumber ?? 'N/A';
    final sector = prefs.getString('sector') ?? 'N/A';
    final floor = prefs.getString('floor') ?? 'N/A';
    final serverHost = prefs.getString('server_host') ?? '192.168.0.183';
    final serverPort = prefs.getString('server_port') ?? '3000';
    final lastSync = prefs.getString('last_sync') ?? 'N/A';
    final authToken = prefs.getString('auth_token') ?? '';
    final batteryLevel = await battery.batteryLevel;

    // Obter IP Address
    String? ipAddress;
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            ipAddress = addr.address;
            break;
          }
        }
      }
    } catch (e) {
      logger.e('Erro ao obter IP Address: $e');
      ipAddress = 'N/A';
    }

    // Obter MAC Address do dispositivo
    String? macAddress;
    try {
      macAddress = await platform.invokeMethod('getMacAddress') ?? 'N/A';
    } catch (e) {
      logger.e('Erro ao obter MAC Address: $e');
      macAddress = 'N/A';
    }

    // Obter informações de Wi-Fi
    List<Map<String, String>> wifiList = [];
    Map<String, String> connectedWifi = {};
    

    try {
      var locationStatus = await Permission.location.request();
      if (!locationStatus.isGranted) {
        logger.e('Permissão de localização negada.');
      } else {
        final wifiScanResult = await WiFiScan.instance.getScannedResults();
        wifiList =
            wifiScanResult
                .map((result) => {'ssid': result.ssid, 'bssid': result.bssid})
                .toList();

        final wifiInfo = await platform.invokeMethod('getWifiInfo');
        if (wifiInfo != null) {
          connectedWifi = {
            'ssid': wifiInfo['ssid']?.replaceAll('"', '') ?? 'N/A',
            'bssid':
                wifiInfo['bssid']?.toLowerCase() ??
                'N/A', // Normalizar para minúsculas
          };
        }

        // Mapeamento de setor e andar com base no BSSID (MAC Address do rádio Wi-Fi)
        
      }
    } catch (e) {
      logger.e('Erro ao obter informações de Wi-Fi: $e');
    }

    this.authToken = authToken;
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
      'mac_address': macAddress,
      'ip_address': ipAddress,
      'network': connectedWifi['ssid'] ?? 'N/A',
      'battery': batteryLevel,
      'last_seen': DateTime.now().toIso8601String(),
      'last_sync':
          lastSync != 'N/A' ? lastSync : DateTime.now().toIso8601String(),
      'wifi_list': wifiList,
      'connected_wifi': connectedWifi,
      
      

       // Versão do aplicativo, pode ser dinâmico
    };
    logger.i('Inicializado: serverUrl=$serverUrl, deviceId=$deviceId');

    // Bloquear configurações (parte já implementada anteriormente)
    await restrictSettings();
  }

  /// Restringe o acesso às configurações do dispositivo (stub para implementação futura)
  Future<void> restrictSettings() async {
    try {
      await platform.invokeMethod('restrictSettings');
      logger.i('Configurações restritas com sucesso.');
    } catch (e) {
      logger.w('Restrição de configurações não implementada ou falhou: $e');
    }
  }

  Future<void> unrestrictSettings() async {
    try {
      final isAdmin = await platform.invokeMethod(
        'isDeviceOwnerOrProfileOwner',
      );
      if (!isAdmin) {
        logger.w(
          'Permissões de administrador necessárias para desbloquear configurações',
        );
        await requestDeviceAdmin();
        return;
      }

      // Desbloquear acesso às configurações
      await platform.invokeMethod('restrictSettings', {'restrict': false});
      logger.i('Configurações do Android desbloqueadas');
    } catch (e) {
      logger.e('Erro ao desbloquear configurações: $e');
    }
  }

  Future<bool> validateServerConnection(String host, String port) async {
    final httpClient = http.Client();
    try {
      final response = await httpClient
          .get(
            Uri.parse('http://$host:$port/api/devices'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(const Duration(seconds: 5));
      logger.i(
        'Validação do servidor: ${response.statusCode} ${response.body}',
      );
      return response.statusCode == 200 ||
          response.statusCode == 401 ||
          response.statusCode == 403;
    } catch (e) {
      logger.e('Erro ao validar conexão com o servidor: $e');
      return false;
    } finally {
      httpClient.close();
    }
  }

  Future<String> sendDeviceData() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) {
      final message = 'Sem conexão ou token inválido';
      logger.e('Erro: $message');
      return message;
    }
    await initialize();

    final httpClient = http.Client();
    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
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

        if (response.statusCode == 200) {
          final prefs = await SharedPreferences.getInstance();
          final lastSync = DateTime.now().toIso8601String();
          await prefs.setString('last_sync', lastSync);
          deviceInfo['last_sync'] = lastSync;
          logger.i('Dados enviados com sucesso: ${response.body}');
          return 'Dados enviados com sucesso';
        } else if (response.statusCode == 401) {
          logger.e('Erro 401: Token inválido');
          return 'Token inválido';
        } else if (response.statusCode == 403) {
          logger.e('Erro 403: Acesso negado');
          return 'Acesso negado';
        } else {
          logger.e('Erro ${response.statusCode}: ${response.body}');
          return 'Erro ${response.statusCode}: ${response.body}';
        }
      } on TimeoutException {
        logger.w('Tentativa $attempts: Timeout ao conectar ao servidor');
        if (attempts == maxRetries) {
          return 'Falha: Tempo limite esgotado após $maxRetries tentativas';
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        logger.w('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          return 'Falha: Não foi possível conectar ao servidor ($e)';
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        logger.e('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          return 'Erro ao enviar dados: $e';
        }
        await Future.delayed(retryDelay);
      } finally {
        httpClient.close();
      }
    }
    return 'Falha após $maxRetries tentativas';
  }

  Future<String> sendHeartbeat() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) {
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
        return 'Heartbeat enviado com sucesso';
      } on TimeoutException {
        logger.w('Tentativa $attempts: Timeout ao enviar heartbeat');
        if (attempts == maxRetries) {
          return 'Falha: Timeout após $maxRetries tentativas';
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        logger.w('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          return 'Falha: Não foi possível conectar ao servidor ($e)';
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        logger.e('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          return 'Erro ao enviar heartbeat: $e';
        }
        await Future.delayed(retryDelay);
      } finally {
        httpClient.close();
      }
    }
    return 'Falha após $maxRetries tentativas';
  }

  Future<void> checkForCommands() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) {
      logger.e('Erro: Sem conexão ou token inválido');
      return;
    }

    final httpClient = http.Client();
    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        final response = await httpClient
            .get(
              Uri.parse('$serverUrl/api/devices/commands?device_id=$deviceId'),
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
          return;
        } else {
          logger.e('Erro ${response.statusCode}: ${response.body}');
          return;
        }
      } on TimeoutException {
        logger.w('Tentativa $attempts: Timeout ao verificar comandos');
        if (attempts == maxRetries) {
          return;
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        logger.w('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          return;
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        logger.e('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          return;
        }
        await Future.delayed(retryDelay);
      } finally {
        httpClient.close();
      }
    }
  }

  Future<void> executeCommand(
    String command,
    String? packageName,
    String? apkUrl,
  ) async {
    bool isAdmin;
    try {
      isAdmin = await platform.invokeMethod('isDeviceOwnerOrProfileOwner');
    } on PlatformException catch (e) {
      logger.e('Erro ao verificar permissões de administrador: $e');
      if (e.code == 'MissingPluginException') {
        logger.e(
          'MethodChannel não encontrado. Verifique a integração com MainActivity.kt',
        );
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

  Future<String> installAppFromUrl(
    String apkUrl, {
    Function(double)? onProgress,
  }) async {
    try {
      final packageName = apkUrl.split('/').last.replaceAll('.apk', '');
      if (packageName.isEmpty) {
        return 'Erro: Nome do pacote inválido na URL';
      }

      if (!Uri.parse(apkUrl).isAbsolute || !apkUrl.endsWith('.apk')) {
        return 'Erro: URL inválida. Deve ser uma URL absoluta terminando com .apk';
      }

      final isAdmin = await platform.invokeMethod(
        'isDeviceOwnerOrProfileOwner',
      );
      if (!isAdmin) {
        logger.w(
          'Permissões de administrador necessárias para instalar aplicativos',
        );
        await requestDeviceAdmin();
        return 'Permissões de administrador necessárias';
      }

      return await installApp(packageName, apkUrl, onProgress: onProgress);
    } catch (e) {
      logger.e('Erro ao instalar aplicativo a partir da URL $apkUrl: $e');
      return 'Erro ao instalar aplicativo: $e';
    }
  }

  Future<String> installApp(
    String packageName,
    String apkUrl, {
    Function(double)? onProgress,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/$packageName.apk');
      logger.i('Baixando APK de $apkUrl para ${apkFile.path}');

      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        logger.e('Erro ao baixar APK: Status ${response.statusCode}');
        throw Exception('Erro ao baixar APK: Status ${response.statusCode}');
      }

      var totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      final fileStream = apkFile.openWrite();
      await response.stream
          .listen(
            (data) {
              receivedBytes += data.length;
              if (totalBytes > 0 && onProgress != null) {
                onProgress((receivedBytes / totalBytes) * 100);
              }
              fileStream.add(data);
            },
            onDone: () async {
              await fileStream.close();
              logger.i('APK baixado com sucesso. Instalando...');
              await platform.invokeMethod('installSystemApp', {
                'apkPath': apkFile.path,
              });
              logger.i('Aplicativo $packageName instalado com sucesso');
            },
            onError: (e) {
              logger.e('Erro ao baixar APK: $e');
              throw Exception('Erro ao baixar APK: $e');
            },
            cancelOnError: true,
          )
          .asFuture();

      return 'Aplicativo $packageName instalado com sucesso';
    } catch (e) {
      logger.e('Erro ao instalar aplicativo: $e');
      rethrow;
    }
  }

  Future<void> uninstallApp(String packageName) async {
    try {
      await platform.invokeMethod('uninstallPackage', {
        'packageName': packageName,
      });
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
      await platform.invokeMethod('installSystemApp', {
        'apkPath': apkFile.path,
      });
      logger.i('Aplicativo $packageName atualizado');
    } catch (e) {
      logger.e('Erro ao atualizar aplicativo: $e');
    }
  }

  Future<void> requestDeviceAdmin() async {
    try {
      await platform.invokeMethod('requestDeviceAdmin', {
        'explanation':
            'MDM Client requer permissões de administrador para gerenciar o dispositivo.',
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
  bool isConnected = false;
  bool isAdmin = false;
  int batteryLevel = 0;
  String lastSync = 'N/A';
  String lastHeartbeatError = '';
  int heartbeatFailureCount = 0;
  bool isServiceRunning = false;
  double installProgress = 0.0;
  bool isInstalling = false;
  bool isUninstalling = false;
  bool isUpdating = false;
  final TextEditingController imeiController = TextEditingController();
  final TextEditingController serialController = TextEditingController();
  final TextEditingController sectorController = TextEditingController();
  final TextEditingController floorController = TextEditingController();
  final TextEditingController serverHostController = TextEditingController();
  final TextEditingController serverPortController = TextEditingController();
  final TextEditingController dataIntervalController = TextEditingController();
  final TextEditingController heartbeatIntervalController =
      TextEditingController();
  final TextEditingController commandCheckIntervalController =
      TextEditingController();
  final TextEditingController tokenController = TextEditingController();
  final TextEditingController apkUrlController = TextEditingController();
  List<String> unwantedApps = ['com.android.chrome', 'com.example.unwantedapp']; // Lista inicial
  final TextEditingController appToDisableController = TextEditingController();
  
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
      isAdminActive = await DeviceService.platform.invokeMethod(
        'isDeviceOwnerOrProfileOwner',
      );
      if (!isAdminActive) {
        await deviceService.requestDeviceAdmin();
      }
    } on PlatformException catch (e) {
      deviceService.logger.e(
        'Erro ao verificar permissões de administrador: $e',
      );
      if (e.code == 'MissingPluginException') {
        deviceService.logger.e(
          'MethodChannel não encontrado. Verifique a integração com MainActivity.kt',
        );
        setState(() {
          statusMessage =
              'Erro: Integração nativa ausente. Reinstale o aplicativo.';
        });
        return;
      }
    }

    setState(() {
      isAdmin = isAdminActive;
      statusMessage =
          isAdmin
              ? 'Permissões de administrador concedidas'
              : 'Permissões de administrador necessárias';
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

    if (isConnected &&
        deviceService.deviceId != null &&
        deviceService.authToken.isNotEmpty) {
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
    final heartbeatInterval =
        int.tryParse(heartbeatIntervalController.text.trim()) ?? 3;
    final commandCheckInterval =
        int.tryParse(commandCheckIntervalController.text.trim()) ?? 1;
    final token = tokenController.text.trim();

    if (imei.isEmpty ||
        serial.isEmpty ||
        sector.isEmpty ||
        floor.isEmpty ||
        serverHost.isEmpty ||
        serverPort.isEmpty ||
        token.isEmpty) {
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

    final isServerReachable = await deviceService.validateServerConnection(
      serverHost,
      serverPort,
    );
    if (!isServerReachable) {
      setState(() {
        statusMessage =
            'Não foi possível conectar ao servidor em $serverHost:$serverPort. Verifique o endereço e a rede.';
      });
      return;
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

    // Definir uma senha padrão se não existir
    final currentPassword = prefs.getString('app_password');
    if (currentPassword == null || currentPassword.isEmpty) {
      await prefs.setString('app_password', '123456'); // Senha padrão
    }

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
    final lastSyncFormatted =
        lastSync != 'N/A'
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
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
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
                              color:
                                  isServiceRunning ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (lastHeartbeatError.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Última falha de heartbeat: $lastHeartbeatError',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                          ),
                        ),
                      ],
                      if (heartbeatFailureCount > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Falhas consecutivas: $heartbeatFailureCount',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                          ),
                        ),
                      ],
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
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nome: ${deviceService.deviceInfo['device_name'] ?? 'N/A'}',
                      ),
                      Text(
                        'Modelo: ${deviceService.deviceInfo['device_model'] ?? 'N/A'}',
                      ),
                      Text(
                        'ID: ${deviceService.deviceInfo['device_id'] ?? 'N/A'}',
                      ),
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
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: imeiController,
                        decoration: InputDecoration(
                          labelText: 'IMEI',
                          prefixIcon: const Icon(Icons.perm_device_information),
                          errorText:
                              imeiController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serialController,
                        decoration: InputDecoration(
                          labelText: 'Número de Série',
                          prefixIcon: const Icon(Icons.confirmation_number),
                          errorText:
                              serialController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sectorController,
                        decoration: InputDecoration(
                          labelText: 'Setor',
                          prefixIcon: const Icon(Icons.business),
                          errorText:
                              sectorController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: floorController,
                        decoration: InputDecoration(
                          labelText: 'Andar',
                          prefixIcon: const Icon(Icons.stairs),
                          errorText:
                              floorController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serverHostController,
                        decoration: InputDecoration(
                          labelText: 'Host do Servidor',
                          prefixIcon: const Icon(Icons.dns),
                          errorText:
                              serverHostController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serverPortController,
                        decoration: InputDecoration(
                          labelText: 'Porta do Servidor',
                          prefixIcon: const Icon(Icons.network_check),
                          errorText:
                              serverPortController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dataIntervalController,
                        decoration: InputDecoration(
                          labelText: 'Intervalo de Dados (minutos)',
                          prefixIcon: const Icon(Icons.timer),
                          errorText:
                              dataIntervalController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: heartbeatIntervalController,
                        decoration: InputDecoration(
                          labelText: 'Intervalo de Heartbeat (minutos)',
                          prefixIcon: const Icon(Icons.favorite),
                          errorText:
                              heartbeatIntervalController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commandCheckIntervalController,
                        decoration: InputDecoration(
                          labelText:
                              'Intervalo de Verificação de Comandos (minutos)',
                          prefixIcon: const Icon(Icons.checklist),
                          errorText:
                              commandCheckIntervalController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenController,
                        decoration: InputDecoration(
                          labelText: 'Token de Autenticação',
                          prefixIcon: const Icon(Icons.vpn_key),
                          errorText:
                              tokenController.text.isEmpty
                                  ? 'Campo obrigatório'
                                  : null,
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
              const SizedBox(height: 16),
// Disable Unwanted Apps Section
Card(
  child: Padding(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Desabilitar Aplicativos Indesejados',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: appToDisableController,
          decoration: InputDecoration(
            labelText: 'Nome do Pacote (ex.: com.android.chrome)',
            prefixIcon: const Icon(Icons.block),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.block),
          label: const Text('Adicionar à Lista'),
          onPressed: () {
            final packageName = appToDisableController.text.trim();
            if (packageName.isNotEmpty) {
              setState(() {
                unwantedApps.add(packageName);
                appToDisableController.clear();
              });
            }
          },
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          itemCount: unwantedApps.length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(unwantedApps[index]),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  setState(() {
                    unwantedApps.removeAt(index);
                  });
                },
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.block),
          label: const Text('Desabilitar Aplicativos'),
          onPressed: () async {
            final result = await deviceService.disableUnwantedApps(unwantedApps);
            setState(() {
              statusMessage = result;
            });
          },
        ),
      ],
    ),
  ),
),
const SizedBox(height: 16),
// ... resto do código (Action Buttons, etc.) ...
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Instalar Aplicativo via QR Code ou URL',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: apkUrlController,
                        decoration: InputDecoration(
                          labelText: 'URL do APK',
                          prefixIcon: const Icon(Icons.link),
                          errorText:
                              apkUrlController.text.isEmpty
                                  ? 'Campo obrigatório para instalação manual'
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('Escanear QR Code'),
                                onPressed: () async {
                                  final scannedUrl = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) =>
                                              const QRCodeScannerScreen(),
                                    ),
                                  );
                                  if (scannedUrl != null) {
                                    setState(() {
                                      apkUrlController.text = scannedUrl;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.download),
                                label: const Text('Instalar APK'),
                                onPressed:
                                    isInstalling
                                        ? null
                                        : () async {
                                          setState(() {
                                            isInstalling = true;
                                            installProgress = 0.0;
                                          });
                                          final apkUrl =
                                              apkUrlController.text.trim();
                                          if (apkUrl.isEmpty) {
                                            setState(() {
                                              statusMessage =
                                                  'Por favor, insira ou escaneie uma URL válida';
                                              isInstalling = false;
                                            });
                                            return;
                                          }
                                          final result = await deviceService
                                              .installAppFromUrl(
                                                apkUrl,
                                                onProgress: (progress) {
                                                  setState(() {
                                                    installProgress = progress;
                                                  });
                                                },
                                              );
                                          setState(() {
                                            statusMessage = result;
                                            isInstalling = false;
                                          });
                                        },
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isInstalling)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: LinearProgressIndicator(
                            value: installProgress / 100,
                            backgroundColor: Colors.grey[300],
                            color: Colors.teal,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Desbloquear Configurações'),
                  onPressed: () async {
                    await deviceService.unrestrictSettings();
                    setState(() {
                      statusMessage = 'Configurações do Android desbloqueadas';
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock),
                  label: const Text('Bloquear Configurações'),
                  onPressed: () async {
                    await deviceService.restrictSettings();
                    setState(() {
                      statusMessage = 'Configurações do Android bloqueadas';
                    });
                  },
                ),
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
                        statusMessage =
                            'Serviço em segundo plano já está ativo';
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

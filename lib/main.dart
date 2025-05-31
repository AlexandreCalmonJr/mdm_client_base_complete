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
import 'package:path_provider/path_provider.dart';
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
      notificationChannelId: 'mdm_client_channel',
      initialNotificationTitle: 'MDM Client Ativo',
      initialNotificationContent: 'Monitorando dispositivo...',
      foregroundServiceNotificationId: 888,
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
  await deviceService.initialize();

  final prefs = await SharedPreferences.getInstance();
  final dataInterval = prefs.getInt('data_interval') ?? 10;
  final heartbeatInterval = prefs.getInt('heartbeat_interval') ?? 3;
  final commandCheckInterval = prefs.getInt('command_check_interval') ?? 1;

  print('Serviço em segundo plano iniciado: ${DateTime.now()}');

  Timer.periodic(Duration(minutes: dataInterval), (_) async {
    final result = await deviceService.sendDeviceData();
    print('Dados enviados: $result');
  });

  int heartbeatFailureCount = prefs.getInt('heartbeat_failure_count') ?? 0;
  Timer.periodic(Duration(minutes: heartbeatInterval), (_) async {
    final result = await deviceService.sendHeartbeat();
    print('Heartbeat: $result${heartbeatFailureCount > 0 ? ', Falhas: $heartbeatFailureCount' : ''}');
    if (result != 'Heartbeat enviado com sucesso') {
      heartbeatFailureCount++;
      await prefs.setString('last_heartbeat_error', '$result às ${DateTime.now().toIso8601String()}');
      await prefs.setInt('heartbeat_failure_count', heartbeatFailureCount);
    } else {
      heartbeatFailureCount = 0;
      await prefs.remove('last_heartbeat_error');
      await prefs.setInt('heartbeat_failure_count', heartbeatFailureCount);
    }
  });

  Timer.periodic(Duration(minutes: commandCheckInterval), (_) async {
    await deviceService.checkForCommands();
  });

  Timer.periodic(const Duration(minutes: 1), (_) async {
    if (service is AndroidServiceInstance && !await service.isForegroundService()) {
      print('Serviço parou inesperadamente. Tentando reiniciar...');
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
<<<<<<< Updated upstream
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16),
=======
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
>>>>>>> Stashed changes
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      home: const MDMClientHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DeviceService {
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');
  String serverUrl = 'http://mdm-server.local:3000';
  String authToken = '';
  final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final Battery battery = Battery();
  final Connectivity connectivity = Connectivity();
  String? deviceId;
  Map<String, dynamic> deviceInfo = {};
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration timeout = Duration(seconds: 10);

  Future<void> initialize() async {
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final prefs = await SharedPreferences.getInstance();
    final imei = prefs.getString('imei') ?? androidInfo.serialNumber ?? 'N/A';
    final serialNumber = prefs.getString('serial_number') ?? androidInfo.serialNumber ?? 'N/A';
    final sector = prefs.getString('sector') ?? 'N/A';
    final floor = prefs.getString('floor') ?? 'N/A';
    final serverHost = prefs.getString('server_host') ?? 'mdm-server.local';
    final serverPort = prefs.getString('server_port') ?? '3000';
    final lastSync = prefs.getString('last_sync') ?? 'N/A';
    final authToken = prefs.getString('auth_token') ?? '';
    final batteryLevel = await battery.batteryLevel;

    this.authToken = authToken;
    serverUrl = 'http://$serverHost:$serverPort';
    deviceId = androidInfo.id;
    deviceInfo = {
      'device_name': androidInfo.device,
      'device_model': androidInfo.model,
      'device_id': androidInfo.id,
      'serial_number': serialNumber,
      'imei': imei,
      'sector': sector,
      'floor': floor,
      'mac_address': 'N/A',
      'ip_address': 'N/A',
      'network': 'N/A',
      'battery': batteryLevel,
      'last_seen': DateTime.now().toIso8601String(),
      'last_sync': lastSync != 'N/A' ? lastSync : DateTime.now().toIso8601String(),
    };
  }

  Future<bool> checkConnectivity() async {
    final connectivityResult = await connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<bool> validateServerConnection(String host, String port) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$host:$port/api/devices'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 || response.statusCode == 401 || response.statusCode == 403;
    } catch (e) {
      print('Erro ao validar conexão com o servidor: $e');
      return false;
    }
  }

  Future<String> sendDeviceData() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) {
      final message = 'Sem conexão ou token inválido';
      print('Erro: $message');
      return message;
    }
    await initialize();

    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        final response = await http
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
          print('Dados enviados com sucesso: ${response.body}');
          return 'Dados enviados com sucesso';
        } else if (response.statusCode == 401) {
          print('Erro 401: Token inválido');
          return 'Token inválido';
        } else if (response.statusCode == 403) {
          print('Erro 403: Acesso negado');
          return 'Acesso negado';
        } else {
          print('Erro ${response.statusCode}: ${response.body}');
          return 'Erro ${response.statusCode}: ${response.body}';
        }
      } on TimeoutException {
        print('Tentativa $attempts: Timeout ao conectar ao servidor');
        if (attempts == maxRetries) {
          return 'Falha: Tempo limite esgotado após $maxRetries tentativas';
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        print('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          return 'Falha: Não foi possível conectar ao servidor ($e)';
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        print('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          return 'Erro ao enviar dados: $e';
        }
        await Future.delayed(retryDelay);
      }
    }
    return 'Falha após $maxRetries tentativas';
  }

  Future<String> sendHeartbeat() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) {
      final message = 'Sem conexão ou token inválido';
      print('Erro: $message');
      return message;
    }

    final host = serverUrl.replaceFirst('http://', '').split(':')[0];
    final port = serverUrl.split(':').length > 2 ? serverUrl.split(':')[2] : '3000';
    if (!await validateServerConnection(host, port)) {
      final message = 'Servidor não acessível: $serverUrl';
      print('Erro: $message');
      return message;
    }

    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        final response = await http
            .post(
              Uri.parse('$serverUrl/api/devices/heartbeat'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $authToken',
              },
              body: jsonEncode({'device_id': deviceId}),
            )
            .timeout(timeout);

        print('Heartbeat enviado: ${response.statusCode} ${response.body}');
        return 'Heartbeat enviado com sucesso';
      } on TimeoutException {
        print('Tentativa $attempts: Timeout ao enviar heartbeat');
        if (attempts == maxRetries) {
          return 'Falha: Timeout após $maxRetries tentativas';
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        print('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          return 'Falha: Não foi possível conectar ao servidor ($e)';
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        print('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          return 'Erro ao enviar heartbeat: $e';
        }
        await Future.delayed(retryDelay);
      }
    }
    return 'Falha após $maxRetries tentativas';
  }

  Future<void> checkForCommands() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) {
      print('Erro: Sem conexão ou token inválido');
      return;
    }

    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        final response = await http
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
          print('Comandos verificados: ${commands.length} comandos');
          return;
        } else {
          print('Erro ${response.statusCode}: ${response.body}');
          return;
        }
      } on TimeoutException {
        print('Tentativa $attempts: Timeout ao verificar comandos');
        if (attempts == maxRetries) {
          return;
        }
        await Future.delayed(retryDelay);
      } on SocketException catch (e) {
        print('Tentativa $attempts: SocketException: $e');
        if (attempts == maxRetries) {
          return;
        }
        await Future.delayed(retryDelay);
      } catch (e) {
        print('Tentativa $attempts: Erro inesperado: $e');
        if (attempts == maxRetries) {
          return;
        }
        await Future.delayed(retryDelay);
      }
    }
  }

  Future<void> executeCommand(String command, String? packageName, String? apkUrl) async {
    final isAdmin = await platform.invokeMethod('isDeviceOwnerOrProfileOwner');
    if (!isAdmin) {
      print('Permissões de administrador necessárias');
      return;
    }

    try {
      switch (command) {
        case 'lock':
          await platform.invokeMethod('lockDevice');
          print('Dispositivo bloqueado');
          break;
        case 'wipe':
          await platform.invokeMethod('wipeData');
          print('Dados apagados');
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
          print('Comando desconhecido: $command');
      }
    } catch (e) {
      print('Erro ao executar comando: $e');
    }
  }

  Future<void> installApp(String packageName, String apkUrl) async {
    try {
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/$packageName.apk');
      final response = await http.get(Uri.parse(apkUrl));
      await apkFile.writeAsBytes(response.bodyBytes);
      await platform.invokeMethod('installSystemApp', {'apkPath': apkFile.path});
      print('Aplicativo $packageName instalado');
    } catch (e) {
      print('Erro ao instalar aplicativo: $e');
    }
  }

  Future<void> uninstallApp(String packageName) async {
    try {
      await platform.invokeMethod('uninstallPackage', {'packageName': packageName});
      print('Aplicativo $packageName desinstalado');
    } catch (e) {
      print('Erro ao desinstalar aplicativo: $e');
    }
  }

  Future<void> updateApp(String packageName, String apkUrl) async {
    try {
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/$packageName.apk');
      final response = await http.get(Uri.parse(apkUrl));
      await apkFile.writeAsBytes(response.bodyBytes);
      await platform.invokeMethod('installSystemApp', {'apkPath': apkFile.path});
      print('Aplicativo $packageName atualizado');
    } catch (e) {
      print('Erro ao atualizar aplicativo: $e');
    }
  }

  Future<void> requestDeviceAdmin() async {
    try {
      await platform.invokeMethod('requestDeviceAdmin', {
        'explanation': 'MDM Client requer permissões de administrador para gerenciar o dispositivo.'
      });
    } catch (e) {
      print('Erro ao solicitar permissões de administrador: $e');
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
    final serverHost = prefs.getString('server_host') ?? 'mdm-server.local';
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

    final isAdminActive = await DeviceService.platform.invokeMethod('isDeviceOwnerOrProfileOwner');
    if (!isAdminActive) {
      await deviceService.requestDeviceAdmin();
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

    final isServerReachable = await deviceService.validateServerConnection(serverHost, serverPort);
    if (!isServerReachable) {
      setState(() {
        statusMessage = 'Não foi possível conectar ao servidor em $serverHost:$serverPort. Verifique o endereço e a rede.';
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
        centerTitle: true,
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: $statusMessage',
              style: TextStyle(
                fontSize: 16,
                color: isConnected ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Serviço em segundo plano: ${isServiceRunning ? 'Ativo' : 'Inativo'}',
              style: TextStyle(
                fontSize: 16,
                color: isServiceRunning ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (lastHeartbeatError.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Última falha de heartbeat: $lastHeartbeatError',
                style: const TextStyle(fontSize: 14, color: Colors.red),
              ),
            ],
            if (heartbeatFailureCount > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Falhas consecutivas de heartbeat: $heartbeatFailureCount',
                style: const TextStyle(fontSize: 14, color: Colors.red),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Informações do Dispositivo',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
            const SizedBox(height: 20),
            Text(
              'Configurações Manuais',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: imeiController,
              decoration: InputDecoration(
                labelText: 'IMEI',
                border: const OutlineInputBorder(),
                errorText: imeiController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: serialController,
              decoration: InputDecoration(
                labelText: 'Número de Série',
                border: const OutlineInputBorder(),
                errorText: serialController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: sectorController,
              decoration: InputDecoration(
                labelText: 'Setor',
                border: const OutlineInputBorder(),
                errorText: sectorController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: floorController,
              decoration: InputDecoration(
                labelText: 'Andar',
                border: const OutlineInputBorder(),
                errorText: floorController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: serverHostController,
              decoration: InputDecoration(
                labelText: 'Host do Servidor (IP ou Hostname)',
                border: const OutlineInputBorder(),
                errorText: serverHostController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: serverPortController,
              decoration: InputDecoration(
                labelText: 'Porta do Servidor',
                border: const OutlineInputBorder(),
                errorText: serverPortController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: dataIntervalController,
              decoration: InputDecoration(
                labelText: 'Intervalo de Dados (minutos)',
                border: const OutlineInputBorder(),
                errorText: dataIntervalController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: heartbeatIntervalController,
              decoration: InputDecoration(
                labelText: 'Intervalo de Heartbeat (minutos)',
                border: const OutlineInputBorder(),
                errorText: heartbeatIntervalController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: commandCheckIntervalController,
              decoration: InputDecoration(
                labelText: 'Intervalo de Verificação de Comandos (minutos)',
                border: const OutlineInputBorder(),
                errorText: commandCheckIntervalController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tokenController,
              decoration: InputDecoration(
                labelText: 'Token de Autenticação',
                border: const OutlineInputBorder(),
                errorText: tokenController.text.isEmpty ? 'Campo obrigatório' : null,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ElevatedButton(
                      onPressed: _saveManualData,
                      child: const Text('Salvar Dados'),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ElevatedButton(
                      onPressed: () async {
                        final result = await deviceService.sendDeviceData();
                        setState(() {
                          statusMessage = result;
                        });
                      },
                      child: const Text('Enviar Dados Agora'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
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
              child: const Text('Verificar/Reiniciar Serviço'),
            ),
          ],
        ),
      ),
    );
  }
}
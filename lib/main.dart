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
      isForegroundMode: true,
      autoStart: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // ✅ CRÍTICO: Configurar como foreground imediatamente
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    
    // Listener para parar o serviço
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  final deviceService = DeviceService();
  await deviceService.initialize();

  final prefs = await SharedPreferences.getInstance();
  final dataInterval = prefs.getInt('data_interval') ?? 10;
  final heartbeatInterval = prefs.getInt('heartbeat_interval') ?? 5;
  final commandCheckInterval = prefs.getInt('command_check_interval') ?? 1;

  // ✅ TIMERS com notificação de foreground
  Timer.periodic(Duration(minutes: dataInterval), (_) async {
    await deviceService.sendDeviceData();
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "MDM Client Ativo",
        content: "Dados enviados: ${DateTime.now().toString().substring(11, 16)}",
      );
    }
  });

  Timer.periodic(Duration(minutes: heartbeatInterval), (_) async {
    await deviceService.sendHeartbeat();
  });

  Timer.periodic(Duration(minutes: commandCheckInterval), (_) async {
    await deviceService.checkForCommands();
  });
}

class MDMClientApp extends StatelessWidget {
  const MDMClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Client',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16),
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
  String serverUrl = 'http://10.71.2.112:3000';
  String authToken = '';
  final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final Battery battery = Battery();
  final Connectivity connectivity = Connectivity();
  String? deviceId;
  Map<String, dynamic> deviceInfo = {};

  Future<void> initialize() async {
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final prefs = await SharedPreferences.getInstance();
    final imei = prefs.getString('imei') ?? androidInfo.serialNumber ?? 'N/A';
    final serialNumber = prefs.getString('serial_number') ?? androidInfo.serialNumber ?? 'N/A';
    final sector = prefs.getString('sector') ?? 'N/A';
    final floor = prefs.getString('floor') ?? 'N/A';
    final serverIp = prefs.getString('server_ip') ?? '10.71.2.112';
    final serverPort = prefs.getString('server_port') ?? '3000';
    final lastSync = prefs.getString('last_sync') ?? 'N/A';
    final authToken = prefs.getString('auth_token') ?? '';
    final batteryLevel = await battery.batteryLevel;

    this.authToken = authToken;
    serverUrl = 'http://$serverIp:$serverPort';
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

  Future<String> sendDeviceData() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) {
      return 'Sem conexão ou token inválido';
    }
    await initialize();

    try {
      // ✅ CORRIGIDO: URL para /api/devices/data
      final response = await http.post(
        Uri.parse('$serverUrl/api/devices/data'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(deviceInfo),
      );
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        final lastSync = DateTime.now().toIso8601String();
        await prefs.setString('last_sync', lastSync);
        deviceInfo['last_sync'] = lastSync;
        print('Dados enviados com sucesso: ${response.statusCode}');
        return 'Dados enviados com sucesso';
      } else if (response.statusCode == 401) {
        return 'Token inválido';
      } else {
        print('Erro ${response.statusCode}: ${response.body}');
        return 'Erro ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      print('Erro ao enviar dados: $e');
      return 'Erro ao enviar dados: $e';
    }
  }

  Future<void> sendHeartbeat() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) return;

    try {
      // ✅ CORRIGIDO: URL para /api/devices/heartbeat
      final response = await http.post(
        Uri.parse('$serverUrl/api/devices/heartbeat'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'device_id': deviceId}),
      );
      print('Heartbeat enviado: ${response.statusCode}');
    } catch (e) {
      print('Erro ao enviar heartbeat: $e');
    }
  }

  Future<void> checkForCommands() async {
    if (!await checkConnectivity() || deviceId == null || authToken.isEmpty) return;

    try {
      // ✅ CORRIGIDO: URL para /api/devices/commands com query parameter
      final response = await http.get(
        Uri.parse('$serverUrl/api/devices/commands?device_id=$deviceId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> commands = jsonDecode(response.body);
        for (var commandData in commands) {
          await executeCommand(
            commandData['command_type'],
            commandData['parameters']?['packageName'],
            commandData['parameters']?['apkUrl'],
          );
        }
      }
    } catch (e) {
      print('Erro ao verificar comandos: $e');
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
  final TextEditingController imeiController = TextEditingController();
  final TextEditingController serialController = TextEditingController();
  final TextEditingController sectorController = TextEditingController();
  final TextEditingController floorController = TextEditingController();
  final TextEditingController serverIpController = TextEditingController();
  final TextEditingController serverPortController = TextEditingController();
  final TextEditingController dataIntervalController = TextEditingController();
  final TextEditingController heartbeatIntervalController = TextEditingController();
  final TextEditingController commandCheckIntervalController = TextEditingController();
  final TextEditingController tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeClient();
  }

  Future<void> _initializeClient() async {
    await deviceService.initialize();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      imeiController.text = prefs.getString('imei') ?? '';
      serialController.text = prefs.getString('serial_number') ?? '';
      sectorController.text = prefs.getString('sector') ?? '';
      floorController.text = prefs.getString('floor') ?? '';
      serverIpController.text = prefs.getString('server_ip') ?? '10.71.2.112';
      serverPortController.text = prefs.getString('server_port') ?? '3000';
      dataIntervalController.text = (prefs.getInt('data_interval') ?? 10).toString();
      heartbeatIntervalController.text = (prefs.getInt('heartbeat_interval') ?? 5).toString();
      commandCheckIntervalController.text = (prefs.getInt('command_check_interval') ?? 1).toString();
      tokenController.text = prefs.getString('auth_token') ?? '';
      lastSync = prefs.getString('last_sync') ?? 'N/A';
    });

    final connectivityResult = await deviceService.checkConnectivity();
    setState(() {
      isConnected = connectivityResult;
      statusMessage = isConnected ? 'Conectado à rede' : 'Sem conexão';
    });

    batteryLevel = await deviceService.battery.batteryLevel;
    setState(() {
      batteryLevel = batteryLevel;
    });

    final isAdminActive = await DeviceService.platform.invokeMethod('isDeviceOwnerOrProfileOwner');
    if (!isAdminActive) {
      await deviceService.requestDeviceAdmin();
    }
    setState(() {
      isAdmin = isAdminActive;
      statusMessage = isAdmin ? 'Permissões de administrador concedidas' : 'Permissões de administrador necessárias';
    });

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
    
    // ✅ ADICIONADO: Iniciar o serviço após configuração
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
    }
  }

  Future<void> _saveManualData() async {
    final prefs = await SharedPreferences.getInstance();
    final imei = imeiController.text.trim();
    final serial = serialController.text.trim();
    final sector = sectorController.text.trim();
    final floor = floorController.text.trim();
    final serverIp = serverIpController.text.trim();
    final serverPort = serverPortController.text.trim();
    final dataInterval = int.tryParse(dataIntervalController.text.trim()) ?? 10;
    final heartbeatInterval = int.tryParse(heartbeatIntervalController.text.trim()) ?? 5;
    final commandCheckInterval = int.tryParse(commandCheckIntervalController.text.trim()) ?? 1;
    final token = tokenController.text.trim();

    if (imei.isEmpty ||
        serial.isEmpty ||
        sector.isEmpty ||
        floor.isEmpty ||
        serverIp.isEmpty ||
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
    if (!RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(serverIp)) {
      setState(() {
        statusMessage = 'IP inválido (ex.: 192.168.1.100)';
      });
      return;
    }
    if (dataInterval < 1 || heartbeatInterval < 1 || commandCheckInterval < 1) {
      setState(() {
        statusMessage = 'Intervalos devem ser maiores que 0';
      });
      return;
    }

    await prefs.setString('imei', imei);
    await prefs.setString('serial_number', serial);
    await prefs.setString('sector', sector);
    await prefs.setString('floor', floor);
    await prefs.setString('server_ip', serverIp);
    await prefs.setString('server_port', serverPort);
    await prefs.setInt('data_interval', dataInterval);
    await prefs.setInt('heartbeat_interval', heartbeatInterval);
    await prefs.setInt('command_check_interval', commandCheckInterval);
    await prefs.setString('auth_token', token);

    deviceService.deviceInfo['imei'] = imei;
    deviceService.deviceInfo['serial_number'] = serial;
    deviceService.deviceInfo['sector'] = sector;
    deviceService.deviceInfo['floor'] = floor;
    deviceService.serverUrl = 'http://$serverIp:$serverPort';
    deviceService.authToken = token;

    setState(() {
      statusMessage = 'Dados salvos com sucesso';
    });

    final result = await deviceService.sendDeviceData();
    setState(() {
      statusMessage = result;
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
              controller: serverIpController,
              decoration: InputDecoration(
                labelText: 'IP do Servidor',
                border: const OutlineInputBorder(),
                errorText: serverIpController.text.isEmpty ? 'Campo obrigatório' : null,
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
            )
          ],
        ),
      ),
    );
  }
}
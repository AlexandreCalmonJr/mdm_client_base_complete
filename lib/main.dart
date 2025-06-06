import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
// ADICIONADO PARA ARMAZENAMENTO SEGURO
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mdm_client_base/login_screen.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apk_manager_screen.dart';
import 'notification_service.dart';
import 'provisioning_status_screen.dart';

// Classe de cliente de API centralizada e segura
class ApiClient {
  final http.Client _client = http.Client();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Logger logger = Logger('ApiClient');
  String _serverUrl = '';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('server_host') ?? '192.168.0.183';
    final port = prefs.getString('server_port') ?? '3000';
    // FORÇAR HTTPS PARA SEGURANÇA
    _serverUrl = 'https://$host:$port';
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _secureStorage.read(key: 'auth_token');
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    await initialize();
    final url = Uri.parse('$_serverUrl$endpoint');
    final headers = await _getHeaders();
    logger.info('POST: $url');
    return _client.post(url, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> get(String endpoint) async {
    await initialize();
    final url = Uri.parse('$_serverUrl$endpoint');
    final headers = await _getHeaders();
    logger.info('GET: $url');
    return _client.get(url, headers: headers).timeout(const Duration(seconds: 15));
  }
}


void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

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
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );
  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final logger = Logger('BackgroundService');
  logger.info('Serviço em segundo plano iniciado: ${DateTime.now()}');

  final deviceService = DeviceService();
  await deviceService.initialize();

  final prefs = await SharedPreferences.getInstance();
  final dataInterval = prefs.getInt('data_interval') ?? 10;
  final heartbeatInterval = prefs.getInt('heartbeat_interval') ?? 3;
  final commandCheckInterval = prefs.getInt('command_check_interval') ?? 1;

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    final now = DateTime.now();
    int minuteCounter = (prefs.getInt('minute_counter') ?? 0) + 1;
    await prefs.setInt('minute_counter', minuteCounter);

    if (minuteCounter % dataInterval == 0) {
      await deviceService.sendDeviceData();
    }
    if (minuteCounter % heartbeatInterval == 0) {
      await deviceService.sendHeartbeat();
    }
    if (minuteCounter % commandCheckInterval == 0) {
      await deviceService.checkForCommands();
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Client',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => HomePage(deviceService: DeviceService()),
        '/provisioning_status': (context) => const ProvisioningStatusScreen(),
        '/apk_manager': (context) => const ApkManagerScreen(),
        '/settings': (context) => const MDMClientHome(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  final DeviceService deviceService;
  const HomePage({super.key, required this.deviceService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MDM Client')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/provisioning_status'), child: const Text('Status de Provisionamento')),
            ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/apk_manager'), child: const Text('Gerenciador de APKs')),
            ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/settings'), child: const Text('Configurações')),
          ],
        ),
      ),
    );
  }
}

// DeviceService Refatorado para usar ApiClient e armazenamento seguro
class DeviceService {
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');
  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final Battery battery = Battery();
  final Logger logger = Logger('DeviceService');

  Map<String, dynamic> deviceInfo = {};

  Future<void> initialize() async {
    await _apiClient.initialize();
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final prefs = await SharedPreferences.getInstance();

    deviceInfo = {
      'device_name': androidInfo.device,
      'device_model': androidInfo.model,
      'device_id': androidInfo.id,
      'serial_number': prefs.getString('serial_number') ?? 'N/A',
      'imei': prefs.getString('imei') ?? 'N/A',
      'battery': await battery.batteryLevel,
      'ip_address': await NetworkInfo().getWifiIP(),
      'mac_address_radio': await NetworkInfo().getWifiBSSID(),
    };
    logger.info('DeviceService inicializado.');
  }

  Future<String> sendDeviceData() async {
    try {
      await initialize();
      final response = await _apiClient.post('/api/devices/data', deviceInfo);
      if (response.statusCode == 200) {
        logger.info('Dados enviados com sucesso.');
        return 'Dados enviados com sucesso';
      }
      logger.warning('Falha ao enviar dados: ${response.statusCode} ${response.body}');
      return 'Falha ao enviar dados: ${response.statusCode}';
    } catch (e) {
      logger.severe('Erro ao enviar dados: $e');
      return 'Erro de conexão ao enviar dados.';
    }
  }

  Future<String> sendHeartbeat() async {
     try {
      final serial = deviceInfo['serial_number'];
      if(serial == null || serial == 'N/A') return 'Serial number não definido.';

      final response = await _apiClient.post('/api/devices/heartbeat', {'serial_number': serial});
      if (response.statusCode == 200) {
        logger.info('Heartbeat enviado com sucesso.');
        return 'Heartbeat enviado com sucesso';
      }
      logger.warning('Falha no heartbeat: ${response.statusCode}');
      return 'Falha no heartbeat: ${response.statusCode}';
    } catch (e) {
      logger.severe('Erro no heartbeat: $e');
      return 'Erro de conexão no heartbeat.';
    }
  }

  Future<void> checkForCommands() async {
    try {
      final serial = deviceInfo['serial_number'];
      if(serial == null || serial == 'N/A') return;
      
      final response = await _apiClient.get('/api/devices/commands?serial_number=$serial');
      if (response.statusCode == 200) {
        final List<dynamic> commands = jsonDecode(response.body);
        logger.info('${commands.length} comandos recebidos.');
        for (var command in commands) {
          // Lógica para executar comando...
        }
      }
    } catch (e) {
      logger.severe('Erro ao verificar comandos: $e');
    }
  }

  // ============== MÉTODO CORRIGIDO ==============
  // O nome do método é 'saveSettings', tudo em minúsculas (camelCase)
  Future<void> saveSettings(Map<String, String> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_host', settings['server_host']!);
    await prefs.setString('server_port', settings['server_port']!);
    await prefs.setString('serial_number', settings['serial_number']!);
    await prefs.setString('imei', settings['imei']!);
    
    await _secureStorage.write(key: 'auth_token', value: settings['auth_token']!);

    logger.info('Configurações salvas com sucesso.');
    await initialize(); // Reinicializa o serviço com as novas configs
  }
}

// MDMClientHome (Tela de Configurações) Refatorada
class MDMClientHome extends StatefulWidget {
  const MDMClientHome({super.key});

  @override
  _MDMClientHomeState createState() => _MDMClientHomeState();
}

class _MDMClientHomeState extends State<MDMClientHome> {
  final _formKey = GlobalKey<FormState>();
  final _deviceService = DeviceService();
  final _secureStorage = const FlutterSecureStorage();

  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _serialController = TextEditingController();
  final _imeiController = TextEditingController();
  final _tokenController = TextEditingController();
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _secureStorage.read(key: 'auth_token');

    setState(() {
      _hostController.text = prefs.getString('server_host') ?? '';
      _portController.text = prefs.getString('server_port') ?? '';
      _serialController.text = prefs.getString('serial_number') ?? '';
      _imeiController.text = prefs.getString('imei') ?? '';
      _tokenController.text = token ?? '';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final settings = {
        'server_host': _hostController.text,
        'server_port': _portController.text,
        'serial_number': _serialController.text,
        'imei': _imeiController.text,
        'auth_token': _tokenController.text,
      };
      
      // ============== CHAMADA CORRIGIDA ==============
      // Chamando o método 'saveSettings' com o nome correto.
      await _deviceService.saveSettings(settings);

      // Reinicia o serviço em background para aplicar as novas configurações
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stopService');
      }
      await initializeService();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas e serviço reiniciado!')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(controller: _hostController, decoration: const InputDecoration(labelText: 'Host do Servidor'), validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null),
                  TextFormField(controller: _portController, decoration: const InputDecoration(labelText: 'Porta do Servidor'), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null),
                  TextFormField(controller: _serialController, decoration: const InputDecoration(labelText: 'Número de Série'), validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null),
                  TextFormField(controller: _imeiController, decoration: const InputDecoration(labelText: 'IMEI'), validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null),
                  TextFormField(controller: _tokenController, decoration: const InputDecoration(labelText: 'Token de Autenticação'), validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('Salvar e Reiniciar Serviço'),
                  )
                ],
              ),
            ),
    );
  }
}

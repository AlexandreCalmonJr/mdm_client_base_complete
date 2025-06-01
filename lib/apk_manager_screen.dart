import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mdm_client_base/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart' show NotificationService;

class ApkManagerScreen extends StatefulWidget {
  const ApkManagerScreen({super.key});

  @override
  _ApkManagerScreenState createState() => _ApkManagerScreenState();
}

class _ApkManagerScreenState extends State<ApkManagerScreen> {
  final Logger _logger = Logger('ApkManagerScreen');
  final DeviceService _deviceService = DeviceService();
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');
  String _serverUrl = 'http://192.168.0.6:3000/public';
  List<Map<String, dynamic>> _apks = [];
  Map<String, bool> _isInstalling = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeServerUrl();
    _fetchApks();
  }

  Future<void> _initializeServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final serverHost = prefs.getString('server_host') ?? '192.168.0.8';
    final serverPort = prefs.getString('server_port') ?? '3000';
    _serverUrl = 'http://$serverHost:$serverPort/public';
    // Adjust for emulator
    if (Platform.isAndroid) {
      _serverUrl;
    }
    _logger.info('Server URL configurado: $_serverUrl');
  }

  Future<void> _fetchApks() async {
    try {
      final response = await http.get(Uri.parse('$_serverUrl/apks.json'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _apks = jsonData.map((item) => {
                'name': item['name'],
                'url': '$_serverUrl/${item['name']}',
                'size': item['size']?.toString() ?? 'N/A',
              }).toList();
          _isLoading = false;
          _logger.info('APKs carregados: ${_apks.length}');
        });
      } else {
        _logger.severe('Falha ao carregar APKs: ${response.statusCode}');
        if (!mounted) return;
        setState(() => _isLoading = false);
        NotificationService.instance.showNotification(
          'Erro',
          'Falha ao carregar APKs: ${response.statusCode}',
        );
      }
    } catch (e) {
      _logger.severe('Erro ao buscar APKs: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      NotificationService.instance.showNotification(
        'Erro',
        'Falha ao carregar APKs: $e',
      );
    }
  }

  // Método melhorado para verificar e solicitar permissões
  Future<bool> _checkAndRequestPermissions() async {
    try {
      final androidVersion = await _getAndroidSdkVersion();
      _logger.info('Versão do Android SDK: $androidVersion');

      if (androidVersion >= 30) {
        // Android 11+ (API 30+) - Usar MANAGE_EXTERNAL_STORAGE
        final manageStorageStatus = await Permission.manageExternalStorage.status;
        _logger.info('Status MANAGE_EXTERNAL_STORAGE: $manageStorageStatus');
        
        if (manageStorageStatus.isDenied || manageStorageStatus.isPermanentlyDenied) {
          final requestResult = await Permission.manageExternalStorage.request();
          _logger.info('Resultado da solicitação MANAGE_EXTERNAL_STORAGE: $requestResult');
          
          if (requestResult.isDenied || requestResult.isPermanentlyDenied) {
            _showPermissionDialog('MANAGE_EXTERNAL_STORAGE');
            return false;
          }
        }
      } else {
        // Android 10 e abaixo - Usar WRITE_EXTERNAL_STORAGE
        final storageStatus = await Permission.storage.status;
        _logger.info('Status STORAGE: $storageStatus');
        
        if (storageStatus.isDenied || storageStatus.isPermanentlyDenied) {
          final requestResult = await Permission.storage.request();
          _logger.info('Resultado da solicitação STORAGE: $requestResult');
          
          if (requestResult.isDenied || requestResult.isPermanentlyDenied) {
            _showPermissionDialog('WRITE_EXTERNAL_STORAGE');
            return false;
          }
        }
      }

      // Verificar também permissão de instalação de aplicativos
      if (androidVersion >= 26) {
        final installStatus = await Permission.requestInstallPackages.status;
        _logger.info('Status REQUEST_INSTALL_PACKAGES: $installStatus');
        
        if (installStatus.isDenied || installStatus.isPermanentlyDenied) {
          final requestResult = await Permission.requestInstallPackages.request();
          _logger.info('Resultado da solicitação REQUEST_INSTALL_PACKAGES: $requestResult');
          
          if (requestResult.isDenied || requestResult.isPermanentlyDenied) {
            _showPermissionDialog('REQUEST_INSTALL_PACKAGES');
            return false;
          }
        }
      }

      _logger.info('Todas as permissões concedidas');
      return true;
    } catch (e) {
      _logger.severe('Erro ao verificar permissões: $e');
      return false;
    }
  }

  void _showPermissionDialog(String permission) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissão Necessária'),
        content: Text(
          'A permissão $permission é necessária para instalar aplicativos.\n\n'
          'Por favor, ative a permissão nas configurações do sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Configurações'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstallApk(String apkName, String apkUrl) async {
  try {
    if (!mounted) return;
    setState(() => _isInstalling[apkName] = true);

    // Verificar permissões primeiro
    final hasPermissions = await _checkAndRequestPermissions();
    if (!hasPermissions) {
      throw Exception('Permissões necessárias não foram concedidas');
    }

    // Download APK
    _logger.info('Baixando APK: $apkUrl');
    final response = await http.get(Uri.parse(apkUrl));
    if (response.statusCode != 200) {
      throw Exception('Falha ao baixar APK: ${response.statusCode}');
    }

    // Determinar diretório de download baseado na versão do Android
    String apkPath;
    final androidVersion = await _getAndroidSdkVersion();
    
    if (androidVersion >= 30) {
      // Android 11+ - usar pasta Downloads pública
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      apkPath = '${downloadsDir.path}/$apkName';
      _logger.info('Android 11+: Salvando em Downloads públicas: $apkPath');
    } else {
      // Android 10 e abaixo - usar armazenamento externo/Downloads
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('Não foi possível acessar o armazenamento externo');
      }
      // Tentar usar a pasta Downloads padrão
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        apkPath = '${downloadsDir.path}/$apkName';
        _logger.info('Android <=10: Usando Downloads públicas: $apkPath');
      } else {
        // Fallback para diretório externo da aplicação
        apkPath = '${externalDir.path}/$apkName';
        _logger.info('Android <=10: Fallback para diretório externo: $apkPath');
      }
    }

    final apkFile = File(apkPath);
    
    // Criar diretório pai se não existir
    await apkFile.parent.create(recursive: true);
    await apkFile.writeAsBytes(response.bodyBytes);
    _logger.info('APK salvo em: $apkPath (${response.bodyBytes.length} bytes)');

    // Verificar se o arquivo foi salvo corretamente
    if (!await apkFile.exists()) {
      throw Exception('Falha ao salvar o arquivo APK em $apkPath');
    }
    
    final fileSize = await apkFile.length();
    _logger.info('Arquivo APK confirmado: $apkPath (${fileSize} bytes)');

    // Instalar APK
    _logger.info('Iniciando instalação de $apkName do caminho: $apkPath');
    final result = await platform.invokeMethod('installSystemApp', {'apkPath': apkPath});
    _logger.info('Instalação concluída: $result');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Instalação de $apkName: $result'),
        backgroundColor: Colors.green,
      ),
    );
    NotificationService.instance.showNotification(
      'Sucesso',
      'Instalação de $apkName concluída',
    );
  } catch (e) {
    _logger.severe('Erro ao instalar APK $apkName: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Falha ao instalar $apkName: $e'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Configurações',
          onPressed: () => openAppSettings(),
        ),
      ),
    );
    NotificationService.instance.showNotification(
      'Erro',
      'Falha ao instalar $apkName: $e',
    );
  } finally {
    if (!mounted) return;
    setState(() => _isInstalling[apkName] = false);
  }
}

  // Helper to get Android SDK version
  Future<int> _getAndroidSdkVersion() async {
    try {
      final result = await platform.invokeMethod('getSdkVersion');
      return result as int;
    } catch (e) {
      _logger.severe('Erro ao obter versão do SDK: $e');
      return 30; // Assumir Android 11+ em caso de erro
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciador de APKs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchApks();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _apks.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.android, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Nenhum APK disponível'),
                      SizedBox(height: 8),
                      Text(
                        'Verifique a conexão com o servidor',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _apks.length,
                  itemBuilder: (context, index) {
                    final apk = _apks[index];
                    final isInstalling = _isInstalling[apk['name']] ?? false;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.android, color: Colors.green),
                        title: Text(
                          apk['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Tamanho: ${apk['size']}'),
                        trailing: isInstalling
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton.icon(
                                onPressed: () =>
                                    _downloadAndInstallApk(apk['name'], apk['url']),
                                icon: const Icon(Icons.download),
                                label: const Text('Instalar'),
                              ),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(apk['name']),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Tamanho: ${apk['size']}'),
                                  const SizedBox(height: 8),
                                  Text('URL: ${apk['url']}'),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Fechar'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _downloadAndInstallApk(apk['name'], apk['url']);
                                  },
                                  child: const Text('Instalar'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
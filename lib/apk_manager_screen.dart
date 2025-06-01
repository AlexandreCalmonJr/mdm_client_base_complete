import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mdm_client_base/main.dart'; // Importe a classe DeviceService
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart' show NotificationService;

class ApkManagerScreen extends StatefulWidget {
  const ApkManagerScreen({super.key});

  @override
  _ApkManagerScreenState createState() => _ApkManagerScreenState();
}

class _ApkManagerScreenState extends State<ApkManagerScreen> {
  final Logger _logger = Logger('ApkManagerScreen');
  final DeviceService _deviceService = DeviceService(); // Instância do DeviceService
  String _serverUrl = 'http://192.168.0.6:3000/public'; // Valor padrão
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
    final serverHost = prefs.getString('server_host') ?? '192.168.0.6';
    final serverPort = prefs.getString('server_port') ?? '3000';
    _serverUrl = 'http://$serverHost:$serverPort/public';
    _logger.info('Server URL configurado: $_serverUrl');
  }

  Future<void> _fetchApks() async {
    try {
      final response = await http.get(Uri.parse('$_serverUrl/apks.json'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        if (!mounted) return; // Verifica se o widget está montado
        setState(() {
          _apks = jsonData.map((item) => {
                'name': item['name'],
                'url': '$_serverUrl/${item['name']}',
                'size': item['size']?.toString() ?? 'N/A',
              }).toList();
          _isLoading = false;
          _logger.info('APKs carregados: $_apks');
        });
      } else {
        _logger.severe('Falha ao carregar os APKs: ${response.statusCode}');
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        NotificationService.instance.showNotification(
            'Erro', 'Falha ao carregar APKs: ${response.statusCode}');
      }
    } catch (e) {
      _logger.severe('Erro ao buscar APKs: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      NotificationService.instance.showNotification(
          'Erro', 'Falha ao carregar APKs: $e');
    }
  }

  Future<void> _downloadAndInstallApk(String apkName, String apkUrl) async {
  try {
    if (!mounted) return;
    setState(() {
      _isInstalling[apkName] = true;
    });
    await _deviceService.installApp(apkName, apkUrl);
    _logger.info('Instalação de $apkName iniciada');
    NotificationService.instance.showNotification(
        'Instalação', 'Instalação de $apkName iniciada');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Instalação de $apkName iniciada')),
    );
  } catch (e) {
    _logger.severe('Erro ao instalar APK $apkName: $e');
    NotificationService.instance.showNotification(
        'Erro', 'Falha ao instalar $apkName: $e');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Falha ao instalar $apkName: $e')),
    );
  } finally {
    if (!mounted) return;
    setState(() {
      _isInstalling[apkName] = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciador de APKs'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _apks.isEmpty
              ? const Center(child: Text('Nenhum APK disponível'))
              : ListView.builder(
                  itemCount: _apks.length,
                  itemBuilder: (context, index) {
                    final apk = _apks[index];
                    final isInstalling = _isInstalling[apk['name']] ?? false;
                    return ListTile(
                      title: Text(apk['name']),
                      subtitle: Text('Tamanho: ${apk['size']}'),
                      trailing: isInstalling
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: () =>
                                  _downloadAndInstallApk(apk['name'], apk['url']),
                              child: const Text('Instalar'),
                            ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(apk['name']),
                            content: Text('Tamanho: ${apk['size']}\nURL: ${apk['url']}'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Fechar'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
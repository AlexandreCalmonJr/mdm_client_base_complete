import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mdm_client_base/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

// Enum para um controlo de estado mais claro
enum InstallStatus { none, downloading, installing }

class ApkManagerScreen extends StatefulWidget {
  const ApkManagerScreen({super.key});

  @override
  State<ApkManagerScreen> createState() => _ApkManagerScreenState();
}

class _ApkManagerScreenState extends State<ApkManagerScreen> with WidgetsBindingObserver {
  final Logger _logger = Logger('ApkManagerScreen');
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');

  List<Map<String, dynamic>> _apks = [];
  final Map<String, (InstallStatus, double)> _installStates = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasInstallPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkPermissionStatus();
    }
  }

  Future<void> _initialize() async {
    await _checkPermissionStatus();
    await _fetchApks();
  }

  Future<void> _checkPermissionStatus() async {
    final status = await Permission.requestInstallPackages.status;
    if (mounted) {
      setState(() {
        _hasInstallPermission = status.isGranted;
      });
    }
  }

  Future<void> _fetchApks() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final serverUrl = Provider.of<DeviceService>(context, listen: false).serverUrl;

    try {
      final response = await http.get(Uri.parse('$serverUrl/public/apks.json')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _apks = jsonData.map((item) => {
                'name': item['name'],
                'url': '$serverUrl/public/${item['name']}',
                'size': _formatBytes(item['size'] ?? 0),
                'version': item['version'] ?? 'N/A',
              }).toList();
        });
      } else {
        throw HttpException('Falha ao carregar APKs: ${response.statusCode}');
      }
    } catch (e) {
      _logger.severe('Erro ao buscar APKs: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível carregar a lista de APKs.\nVerifique a conexão com o servidor.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes.toString().length - 1) ~/ 3;
    return '${(bytes / (1 << (i * 10))).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _handleInstallClick(String apkName, String apkUrl) async {
    await _checkPermissionStatus();
    if (_hasInstallPermission) {
      _showInstallConfirmation(apkName, apkUrl);
    } else {
      _showPermissionExplanationDialog();
    }
  }

  Future<void> _downloadAndInstallApk(String apkName, String apkUrl) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) throw Exception('Falha no download: ${response.statusCode}');

      final contentLength = response.contentLength;
      List<int> bytes = [];
      int received = 0;

      response.stream.listen(
        (List<int> newBytes) {
          bytes.addAll(newBytes);
          received += newBytes.length;
          if (contentLength != null && mounted) {
            setState(() => _installStates[apkName] = (InstallStatus.downloading, received / contentLength));
          }
        },
        onDone: () async {
          if (mounted) setState(() => _installStates[apkName] = (InstallStatus.installing, 1.0));
          
          // **INÍCIO DA CORREÇÃO: Guarda o ficheiro no diretório temporário da aplicação**
          final tempDir = await getTemporaryDirectory();
          final apkFile = File('${tempDir.path}/$apkName');
          await apkFile.writeAsBytes(bytes);
          _logger.info('APK salvo em: ${apkFile.path}');
          // **FIM DA CORREÇÃO**

          // A lógica de "Device Owner vs Normal" está no lado nativo (MainActivity.kt)
          final result = await platform.invokeMethod('installSystemApp', {'apkPath': apkFile.path});
          _logger.info('Instalação concluída: $result');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Instalação de $apkName: $result'), backgroundColor: Colors.green));
          }
        },
        onError: (e) => throw e,
        cancelOnError: true,
      );
    } catch (e) {
      _logger.severe('Erro ao instalar APK $apkName: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao instalar $apkName: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        final currentState = _installStates[apkName];
        if (currentState?.$1 != InstallStatus.downloading) {
            setState(() => _installStates[apkName] = (InstallStatus.none, 0.0));
        }
      }
    }
  }

  Future<void> _showInstallConfirmation(String apkName, String apkUrl) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Instalação'),
        content: Text('Tem a certeza de que deseja instalar o aplicativo "$apkName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadAndInstallApk(apkName, apkUrl);
            },
            child: const Text('Instalar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionExplanationDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissão Necessária'),
        content: const Text('Para instalar aplicações a partir deste gerenciador, é necessário conceder permissão para instalar aplicações de fontes desconhecidas nas configurações do Android.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings(); // Abre as configurações da aplicação
            },
            child: const Text('Ir para Configurações'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciador de Aplicações'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchApks,
              child: Column(
                children: [
                  _buildPermissionCard(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionCard() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      color: _hasInstallPermission ? Colors.green.shade50 : Colors.orange.shade50,
      child: ListTile(
        leading: Icon(
          _hasInstallPermission ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
          color: _hasInstallPermission ? Colors.green : Colors.orange,
          size: 32,
        ),
        title: Text(
          'Permissão para Instalar Aplicações',
          style: TextStyle(fontWeight: FontWeight.bold, color: _hasInstallPermission ? Colors.green.shade800 : Colors.orange.shade800),
        ),
        subtitle: Text(_hasInstallPermission ? 'Ativa' : 'Inativa. É necessária para instalar APKs.'),
        trailing: !_hasInstallPermission
            ? ElevatedButton(onPressed: openAppSettings, child: const Text('Ativar'))
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) return _buildErrorWidget();
    if (_apks.isEmpty) return const Center(child: Text('Nenhum APK disponível no servidor.'));

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _apks.length,
      itemBuilder: (context, index) {
        final apk = _apks[index];
        return _buildApkCard(apk);
      },
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.grey[400], size: 80),
            const SizedBox(height: 24),
            const Text('Ocorreu um Erro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchApks,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApkCard(Map<String, dynamic> apk) {
    final apkName = apk['name'] as String;
    final state = _installStates[apkName] ?? (InstallStatus.none, 0.0);
    final status = state.$1;
    final progress = state.$2;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.android_rounded, color: Colors.green, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(apkName.replaceAll('.apk', ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Versão: ${apk['version']} • Tamanho: ${apk['size']}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _buildInstallButton(status, progress, apk),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallButton(InstallStatus status, double progress, Map<String, dynamic> apk) {
    switch (status) {
      case InstallStatus.none:
        return ElevatedButton(
          onPressed: () => _handleInstallClick(apk['name'], apk['url']),
          child: const Text('Instalar'),
        );
      case InstallStatus.downloading:
        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(value: progress),
              Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      case InstallStatus.installing:
        return const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(),
        );
    }
  }
}

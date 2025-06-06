import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:mdm_client_base/main.dart';
import 'package:mdm_client_base/notification_service.dart';
// Importe o DeviceService

 // Supondo que este seja o pacote base para MDM

/// Tela para exibir o status de provisionamento do dispositivo
class ProvisioningStatusScreen extends StatefulWidget {
  const ProvisioningStatusScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _ProvisioningStatusScreenState createState() => _ProvisioningStatusScreenState();
}

class _ProvisioningStatusScreenState extends State<ProvisioningStatusScreen> {
  final Logger _logger = Logger('ProvisioningStatusScreen');
  String _status = 'Checking...';
  String? _errorMessage;
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');

  @override
 @override
void initState() {
  super.initState();
  _fetchAndApplyProvisioningExtras();
}

Future<void> _fetchAndApplyProvisioningExtras() async {
  try {
    // Chama o método nativo para obter os dados do QR Code
    final Map<dynamic, dynamic>? extras = await platform.invokeMethod('getProvisioningExtras');
    
    if (extras != null) {
      final String? serverHost = extras['server_host'];
      final String? serverPort = extras['server_port'];
      final String? authToken = extras['auth_token'];

      // LOG IMPORTANTE: Verifique se os dados estão corretos
      print('Dados de provisionamento recebidos: $extras');

      if (serverHost != null && serverPort != null && authToken != null) {
        // Agora, salve essas informações de forma segura e configure o app
        final deviceService = DeviceService(); // Sua classe de serviço
        await deviceService.saveSettings({
            'server_host': serverHost,
            'server_port': serverPort,
            'auth_token': authToken,
            // Preencha outros campos como serial/imei se necessário ou deixe para depois
            'serial_number': 'PROVISIONED-${DateTime.now().millisecondsSinceEpoch}',
            'imei': '',
        });
        
        setState(() {
          _status = 'Provisionado com sucesso via QR Code!';
        });
        
        // Inicie o envio de dados para o servidor
        await deviceService.sendDeviceData();

      } else {
        setState(() => _status = 'Falha: Dados de provisionamento incompletos.');
      }
    } else {
       setState(() => _status = 'Dispositivo não provisionado via QR Code.');
    }
  } catch (e) {
    setState(() => _status = 'Erro ao buscar dados de provisionamento: $e');
  }
}


  Future<void> _checkProvisioningStatus() async {
    try {
      final isDeviceOwner = await platform.invokeMethod('isDeviceOwnerOrProfileOwner');
      setState(() {
        _status = isDeviceOwner ? 'Provisioned Successfully' : 'Not Provisioned';
        _logger.info('Provisioning status: $_status');
      });
    } catch (e) {
      setState(() {
        _status = 'Error';
        _errorMessage = 'Failed to check provisioning: $e';
        _logger.severe(_errorMessage);
      });
    }
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'provisioningComplete') {
        final status = call.arguments['status'];
        setState(() {
          _status = status == 'success' ? 'Provisioned Successfully' : 'Provisioning Failed';
          _errorMessage = status == 'failed' ? call.arguments['error'] : null;
          _logger.info('Provisioning update: $_status, Error: $_errorMessage');
        });
      } else if (call.method == 'provisioningFailure' || call.method == 'policyFailure') {
        setState(() {
          _status = 'Error';
          _errorMessage = call.arguments['error'];
          _logger.severe('Failure: ${call.method}, Error: $_errorMessage');
        });
        _showNotification(call.method, _errorMessage ?? 'Unknown error');
      }
    });
  }

  void _showNotification(String title, String message) {
    NotificationService.instance.showNotification(title, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status de Provisionamento'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Status: $_status',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    'Erro: $_errorMessage',
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                  ),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _checkProvisioningStatus,
                child: const Text('Verificar Novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
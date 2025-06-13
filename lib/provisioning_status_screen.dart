import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:mdm_client_base/notification_service.dart';

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
  void initState() {
    super.initState();
    _logger.info('Initializing ProvisioningStatusScreen');
    NotificationService.instance.initialize();
    _checkProvisioningStatus();
    _setupMethodChannel();
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
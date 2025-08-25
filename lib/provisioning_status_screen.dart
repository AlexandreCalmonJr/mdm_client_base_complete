import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class ImprovedProvisioningScreen extends StatefulWidget {
  const ImprovedProvisioningScreen({super.key});

  @override
  State<ImprovedProvisioningScreen> createState() =>
      _ImprovedProvisioningScreenState();
}

class _ImprovedProvisioningScreenState extends State<ImprovedProvisioningScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  ProvisioningStatus _status = ProvisioningStatus.checking;
  String? _errorMessage;

  static const platform =
      MethodChannel('com.example.mdm_client_base/device_policy');

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkProvisioningStatus();
  }

  void _setupAnimations() {
    _pulseController =
        AnimationController(duration: const Duration(seconds: 2), vsync: this);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _pulseController.repeat(reverse: true);
  }

  Future<void> _checkProvisioningStatus() async {
    setState(() {
      _status = ProvisioningStatus.checking;
      _errorMessage = null;
    });

    try {
      // Pequeno delay para melhorar a percepção do usuário
      await Future.delayed(const Duration(seconds: 1));
      
      final isDeviceOwner =
          await platform.invokeMethod('isDeviceOwnerOrProfileOwner');
      
      if (mounted) {
        setState(() {
          _status = isDeviceOwner
              ? ProvisioningStatus.provisioned
              : ProvisioningStatus.notProvisioned;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = ProvisioningStatus.error;
          _errorMessage = 'Falha na verificação: $e';
        });
      }
    } finally {
      if (mounted) {
        _pulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status de Provisionamento'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(context),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _status == ProvisioningStatus.checking
                  ? null
                  : _checkProvisioningStatus,
              icon: const Icon(Icons.refresh),
              label: Text(_status == ProvisioningStatus.checking
                  ? 'Verificando...'
                  : 'Verificar Novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final color = _getStatusColor();
    final title = _getStatusTitle();
    final description = _getStatusDescription();

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildStatusIcon(),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    final color = _getStatusColor();
    IconData iconData;

    switch (_status) {
      case ProvisioningStatus.checking:
        iconData = Icons.sync;
        break;
      case ProvisioningStatus.provisioned:
        iconData = Icons.verified_user;
        break;
      case ProvisioningStatus.notProvisioned:
        iconData = Icons.warning_amber;
        break;
      case ProvisioningStatus.error:
        iconData = Icons.error;
        break;
    }

    Widget icon = Icon(iconData, size: 64, color: color);

    if (_status == ProvisioningStatus.checking) {
      icon = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _pulseAnimation.value, child: child);
        },
        child: icon,
      );
    }

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Center(child: icon),
    );
  }

  // Métodos auxiliares
  String _getStatusTitle() {
    switch (_status) {
      case ProvisioningStatus.checking:
        return 'Verificando...';
      case ProvisioningStatus.provisioned:
        return 'Dispositivo Provisionado';
      case ProvisioningStatus.notProvisioned:
        return 'Não Provisionado';
      case ProvisioningStatus.error:
        return 'Erro na Verificação';
    }
  }

  String _getStatusDescription() {
    switch (_status) {
      case ProvisioningStatus.checking:
        return 'Aguarde enquanto verificamos o status.';
      case ProvisioningStatus.provisioned:
        return 'O dispositivo está configurado e pronto para uso.';
      case ProvisioningStatus.notProvisioned:
        return 'O dispositivo precisa ser configurado como "dono do dispositivo".';
      case ProvisioningStatus.error:
        return 'Ocorreu um erro durante a verificação.';
    }
  }

  Color _getStatusColor() {
    switch (_status) {
      case ProvisioningStatus.checking:
        return Colors.blue;
      case ProvisioningStatus.provisioned:
        return Colors.green;
      case ProvisioningStatus.notProvisioned:
        return Colors.orange;
      case ProvisioningStatus.error:
        return Colors.red;
    }
  }
}

enum ProvisioningStatus {
  checking,
  provisioned,
  notProvisioned,
  error,
}

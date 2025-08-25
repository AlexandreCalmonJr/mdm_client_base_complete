import 'package:flutter/material.dart';
import 'package:mdm_client_base/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _imeiController;
  late final TextEditingController _serialController;
  late final TextEditingController _sectorController;
  late final TextEditingController _floorController;
  late final TextEditingController _serverHostController;
  late final TextEditingController _serverPortController;
  late final TextEditingController _tokenController;
  late final TextEditingController _dataIntervalController;
  late final TextEditingController _heartbeatIntervalController;
  late final TextEditingController _commandCheckIntervalController;

  @override
  void initState() {
    super.initState();
    _imeiController = TextEditingController();
    _serialController = TextEditingController();
    _sectorController = TextEditingController();
    _floorController = TextEditingController();
    _serverHostController = TextEditingController();
    _serverPortController = TextEditingController();
    _tokenController = TextEditingController();
    _dataIntervalController = TextEditingController();
    _heartbeatIntervalController = TextEditingController();
    _commandCheckIntervalController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _imeiController.text = prefs.getString('imei') ?? '';
    _serialController.text = prefs.getString('serial_number') ?? '';
    _sectorController.text = prefs.getString('sector') ?? '';
    _floorController.text = prefs.getString('floor') ?? '';
    _serverHostController.text = prefs.getString('server_host') ?? '192.168.0.183';
    _serverPortController.text = prefs.getString('server_port') ?? '3000';
    _tokenController.text = prefs.getString('auth_token') ?? '';
    _dataIntervalController.text = (prefs.getInt('data_interval') ?? 10).toString();
    _heartbeatIntervalController.text = (prefs.getInt('heartbeat_interval') ?? 3).toString();
    _commandCheckIntervalController.text = (prefs.getInt('command_check_interval') ?? 1).toString();
  }

  @override
  void dispose() {
    _imeiController.dispose();
    _serialController.dispose();
    _sectorController.dispose();
    _floorController.dispose();
    _serverHostController.dispose();
    _serverPortController.dispose();
    _tokenController.dispose();
    _dataIntervalController.dispose();
    _heartbeatIntervalController.dispose();
    _commandCheckIntervalController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final deviceService = Provider.of<DeviceService>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      final bool wasConfigured = (prefs.getString('serial_number') ?? '').isNotEmpty;

      await deviceService.saveSettings(
        imei: _imeiController.text,
        serial: _serialController.text,
        sector: _sectorController.text,
        floor: _floorController.text,
        serverHost: _serverHostController.text,
        serverPort: _serverPortController.text,
        token: _tokenController.text,
        dataInterval: int.tryParse(_dataIntervalController.text) ?? 10,
        heartbeatInterval: int.tryParse(_heartbeatIntervalController.text) ?? 3,
        commandCheckInterval: int.tryParse(_commandCheckIntervalController.text) ?? 1,
      );

      // Verificar e solicitar permissões
      if (!deviceService.isAdmin) {
        debugPrint("Solicitando permissão de administrador...");
        final bool adminGranted = await deviceService.requestDeviceAdmin();
        debugPrint("Resultado da permissão de administrador: $adminGranted");
        if (!adminGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissões de administrador são necessárias para continuar.')),
          );
          return;
        }
      }

      if (!deviceService.hasLocationPermission) {
        debugPrint("Solicitando permissão de localização...");
        final bool locationGranted = await deviceService.requestLocationPermission();
        debugPrint("Resultado da permissão de localização: $locationGranted");
        if (!locationGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissões de localização são necessárias para continuar.')),
          );
          return;
        }
      }

      if (!deviceService.hasNotificationPermission) {
        debugPrint("Solicitando permissão de notificação...");
        final bool notificationGranted = await deviceService.requestNotificationPermission();
        debugPrint("Resultado da permissão de notificação: $notificationGranted");
        if (!notificationGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissões de notificação são necessárias para continuar.')),
          );
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas com sucesso!')),
        );
        if (!wasConfigured) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        } else {
          Navigator.pop(context);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle('Dispositivo'),
              _buildTextFormField(_serialController, 'Número de Série', Icons.confirmation_number),
              _buildTextFormField(_imeiController, 'IMEI', Icons.perm_device_information),
              const SizedBox(height: 24),
              _buildSectionTitle('Localização'),
              _buildTextFormField(_sectorController, 'Setor', Icons.business),
              _buildTextFormField(_floorController, 'Andar', Icons.stairs),
              const SizedBox(height: 24),
              _buildSectionTitle('Servidor'),
              _buildTextFormField(_serverHostController, 'Host do Servidor', Icons.dns),
              _buildTextFormField(_serverPortController, 'Porta do Servidor', Icons.network_check, keyboardType: TextInputType.number),
              _buildTextFormField(_tokenController, 'Token de Autenticação', Icons.vpn_key),
              const SizedBox(height: 24),
              _buildSectionTitle('Intervalos (em minutos)'),
              _buildTextFormField(_dataIntervalController, 'Envio de Dados', Icons.timer, keyboardType: TextInputType.number),
              _buildTextFormField(_heartbeatIntervalController, 'Heartbeat', Icons.favorite, keyboardType: TextInputType.number),
              _buildTextFormField(_commandCheckIntervalController, 'Verificação de Comandos', Icons.checklist, keyboardType: TextInputType.number),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text('Salvar Configurações'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTextFormField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
        keyboardType: keyboardType,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Este campo é obrigatório';
          }
          if (keyboardType == TextInputType.number && int.tryParse(value) == null) {
            return 'Por favor, insira um número válido';
          }
          return null;
        },
      ),
    );
  }
}
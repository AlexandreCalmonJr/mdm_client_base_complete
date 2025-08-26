import 'package:flutter/material.dart';
import 'package:mdm_client_base/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
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
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isLoading = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _initAnimations();
    _loadSettings();
  }

  void _initControllers() {
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
  }

  void _initAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    
    await Future.delayed(const Duration(milliseconds: 500)); // Simular carregamento
    
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
    
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _animationController.dispose();
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
      setState(() => _isLoading = true);
      
      try {
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
            _showErrorSnackBar('Permissões de administrador são necessárias para continuar.');
            return;
          }
        }

        if (!deviceService.hasLocationPermission) {
          debugPrint("Solicitando permissão de localização...");
          final bool locationGranted = await deviceService.requestLocationPermission();
          debugPrint("Resultado da permissão de localização: $locationGranted");
          if (!locationGranted) {
            _showErrorSnackBar('Permissões de localização são necessárias para continuar.');
            return;
          }
        }

        if (!deviceService.hasNotificationPermission) {
          debugPrint("Solicitando permissão de notificação...");
          final bool notificationGranted = await deviceService.requestNotificationPermission();
          debugPrint("Resultado da permissão de notificação: $notificationGranted");
          if (!notificationGranted) {
            _showErrorSnackBar('Permissões de notificação são necessárias para continuar.');
            return;
          }
        }

        if (mounted) {
          _showSuccessSnackBar('Configurações salvas com sucesso!');
          if (!wasConfigured) {
            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          } else {
            Navigator.pop(context);
          }
        }
      } catch (e) {
        _showErrorSnackBar('Erro ao salvar configurações: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Configurações',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark 
                ? [Colors.blue.shade800, Colors.blue.shade600]
                : [Colors.blue.shade600, Colors.blue.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
              ? [Colors.grey.shade900, Colors.grey.shade800]
              : [Colors.grey.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading 
          ? _buildLoadingScreen()
          : FadeTransition(
              opacity: _fadeAnimation,
              child: _buildSettingsForm(),
            ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Carregando configurações...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSettingsCard(
              'Dispositivo',
              Icons.phone_android,
              Colors.blue,
              [
                _buildModernTextFormField(
                  _serialController,
                  'Número de Série',
                  Icons.confirmation_number,
                ),
                _buildModernTextFormField(
                  _imeiController,
                  'IMEI',
                  Icons.perm_device_information,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSettingsCard(
              'Localização',
              Icons.location_on,
              Colors.green,
              [
                _buildModernTextFormField(
                  _sectorController,
                  'Setor',
                  Icons.business,
                ),
                _buildModernTextFormField(
                  _floorController,
                  'Andar',
                  Icons.stairs,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSettingsCard(
              'Servidor',
              Icons.cloud,
              Colors.purple,
              [
                _buildModernTextFormField(
                  _serverHostController,
                  'Host do Servidor',
                  Icons.dns,
                ),
                _buildModernTextFormField(
                  _serverPortController,
                  'Porta do Servidor',
                  Icons.network_check,
                  keyboardType: TextInputType.number,
                ),
                _buildTokenField(),
              ],
            ),
            const SizedBox(height: 24),
            _buildSettingsCard(
              'Intervalos (em minutos)',
              Icons.timer,
              Colors.orange,
              [
                _buildModernTextFormField(
                  _dataIntervalController,
                  'Envio de Dados',
                  Icons.upload,
                  keyboardType: TextInputType.number,
                ),
                _buildModernTextFormField(
                  _heartbeatIntervalController,
                  'Heartbeat',
                  Icons.favorite,
                  keyboardType: TextInputType.number,
                ),
                _buildModernTextFormField(
                  _commandCheckIntervalController,
                  'Verificação de Comandos',
                  Icons.checklist,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(String title, IconData titleIcon, Color accentColor, List<Widget> children) {
    return Card(
      elevation: 8,
      shadowColor: accentColor.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              accentColor.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(titleIcon, color: accentColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextFormField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          labelStyle: TextStyle(color: Colors.grey.shade600),
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

  Widget _buildTokenField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: _tokenController,
        obscureText: _obscureToken,
        decoration: InputDecoration(
          labelText: 'Token de Autenticação',
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.vpn_key, size: 20),
          ),
          suffixIcon: IconButton(
            icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscureToken = !_obscureToken),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          labelStyle: TextStyle(color: Colors.grey.shade600),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Este campo é obrigatório';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade400],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _saveSettings,
        icon: _isLoading 
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.save, color: Colors.white),
        label: Text(
          _isLoading ? 'Salvando...' : 'Salvar Configurações',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
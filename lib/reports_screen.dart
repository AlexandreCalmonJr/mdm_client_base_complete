import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:mdm_client_base/main.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart'; // Adicione esta dependência no pubspec.yaml

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  List<AppInfo>? _installedApps;
  bool _isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _getInstalledApps();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _getInstalledApps() async {
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      apps.sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
      if (mounted) {
        setState(() {
          _installedApps = apps;
          _isLoading = false;
        });
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _animationController.forward();
      }
      debugPrint("Erro ao carregar aplicativos: $e");
    }
  }

  String _generateDeviceInfoJson(Map<String, dynamic> deviceInfo) {
    final selectedInfo = {
      'device_name': deviceInfo['device_name'],
      'device_model': deviceInfo['device_model'],
      'serial_number': deviceInfo['serial_number'],
      'ip_address': deviceInfo['ip_address'],
      'timestamp': DateTime.now().toIso8601String(),
    };
    return jsonEncode(selectedInfo);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Informações copiadas para a área de transferência'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceService = Provider.of<DeviceService>(context, listen: false);
    final deviceInfo = deviceService.deviceInfo;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Relatórios do Dispositivo'),
        elevation: 0,
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _getInstalledApps();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Carregando informações...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  // Tabs personalizadas
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTabButton('Dispositivo', 0, Icons.phone_android),
                        ),
                        Expanded(
                          child: _buildTabButton('Rede', 1, Icons.wifi),
                        ),
                        Expanded(
                          child: _buildTabButton('QR Code', 2, Icons.qr_code),
                        ),
                        Expanded(
                          child: _buildTabButton('Apps', 3, Icons.apps),
                        ),
                      ],
                    ),
                  ),
                  // Conteúdo das tabs
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildTabContent(deviceInfo),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTabButton(String title, int index, IconData icon) {
    final isSelected = _selectedTabIndex == index;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[600],
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(Map<String, dynamic> deviceInfo) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildDeviceInfoTab(deviceInfo);
      case 1:
        return _buildNetworkInfoTab(deviceInfo);
      case 2:
        return _buildQRCodeTab(deviceInfo);
      case 3:
        return _buildAppsTab();
      default:
        return Container();
    }
  }

  Widget _buildDeviceInfoTab(Map<String, dynamic> deviceInfo) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildEnhancedInfoCard(
          'Informações do Dispositivo',
          deviceInfo,
          [
            'device_name',
            'device_model',
            'device_id',
            'serial_number',
            'imei',
            'secure_android_id',
          ],
          Icons.phone_android,
          Colors.blue,
        ),
      ],
    );
  }

  Widget _buildNetworkInfoTab(Map<String, dynamic> deviceInfo) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildEnhancedInfoCard(
          'Informações de Rede',
          deviceInfo,
          [
            'network',
            'ip_address',
            'mac_address_radio',
            'wifi_gateway_ip',
            'wifi_submask',
          ],
          Icons.wifi,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildQRCodeTab(Map<String, dynamic> deviceInfo) {
    final qrData = _generateDeviceInfoJson(deviceInfo);
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.qr_code,
                  size: 40,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'QR Code do Dispositivo',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Escaneie para obter informações básicas do dispositivo',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _copyToClipboard(qrData),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar Dados'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple.shade400, Colors.purple.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.apps, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Aplicativos Instalados',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_installedApps?.length ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: _installedApps?.isNotEmpty == true
                    ? ListView.builder(
                        shrinkWrap: true,
                        itemCount: _installedApps!.length,
                        itemBuilder: (context, index) {
                          final app = _installedApps![index];
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: index.isEven ? Colors.grey[50] : Colors.white,
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 45,
                                height: 45,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey[200],
                                ),
                                child: app.icon != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          app.icon!,
                                          width: 45,
                                          height: 45,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(Icons.apps, color: Colors.grey),
                              ),
                              title: Text(
                                app.name ?? 'App Desconhecido',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                app.packageName ?? '',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      )
                    : const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nenhum aplicativo encontrado.'),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedInfoCard(
    String title,
    Map<String, dynamic> data,
    List<String> keys,
    IconData icon,
    Color accentColor,
  ) {
    const keyMappings = {
      'device_name': 'Nome do Dispositivo',
      'device_model': 'Modelo',
      'device_id': 'ID da Build',
      'serial_number': 'Número de Série',
      'imei': 'IMEI',
      'secure_android_id': 'Android ID',
      'network': 'Rede Wi-Fi',
      'ip_address': 'Endereço IP',
      'mac_address_radio': 'Endereço MAC (BSSID)',
      'wifi_gateway_ip': 'Gateway',
      'wifi_submask': 'Máscara de Sub-rede',
    };

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.withOpacity(0.7), accentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: keys.map((key) {
                final displayName = keyMappings[key] ?? key;
                final value = data[key]?.toString() ?? 'N/A';
                final isNA = value == 'N/A';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Text(
                          value,
                          style: TextStyle(
                            color: isNA ? Colors.grey[400] : Colors.grey[700],
                            fontSize: 14,
                            fontFamily: value.length > 20 ? 'monospace' : null,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
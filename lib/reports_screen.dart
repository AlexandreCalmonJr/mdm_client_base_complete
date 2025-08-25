import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:mdm_client_base/main.dart';
import 'package:provider/provider.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<AppInfo>? _installedApps;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _getInstalledApps();
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // Lidar com o erro, se necessário
      debugPrint("Erro ao carregar aplicativos: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Acede ao DeviceService para obter os dados do dispositivo e da rede
    final deviceService = Provider.of<DeviceService>(context, listen: false);
    final deviceInfo = deviceService.deviceInfo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios do Dispositivo'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                _buildInfoCard('Informações do Dispositivo', deviceInfo, [
                  'device_name',
                  'device_model',
                  'device_id',
                  'serial_number',
                  'imei',
                  'secure_android_id',
                ]),
                _buildInfoCard('Informações de Rede', deviceInfo, [
                  'network',
                  'ip_address',
                  'mac_address_radio',
                  'wifi_gateway_ip',
                  'wifi_submask',
                ]),
                _buildAppListCard(),
              ],
            ),
    );
  }

  Widget _buildInfoCard(String title, Map<String, dynamic> data, List<String> keys) {
    // Mapeamento de chaves para nomes mais amigáveis
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
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            ...keys.map((key) {
              final displayName = keyMappings[key] ?? key;
              final value = data[key]?.toString() ?? 'N/A';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$displayName:', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppListCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ExpansionTile(
        title: Text('Aplicativos Instalados (${_installedApps?.length ?? 0})', style: Theme.of(context).textTheme.titleLarge),
        children: _installedApps?.map((app) {
          return ListTile(
            leading: app.icon != null ? Image.memory(app.icon!, width: 40, height: 40) : const Icon(Icons.apps),
            title: Text(app.name ?? 'App Desconhecido'),
            subtitle: Text(app.packageName ?? ''),
          );
        }).toList() ?? [const ListTile(title: Text('Nenhum aplicativo encontrado.'))],
      ),
    );
  }
}

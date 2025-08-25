import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppBlockerSettingsScreen extends StatefulWidget {
  const AppBlockerSettingsScreen({super.key});

  @override
  State<AppBlockerSettingsScreen> createState() => _AppBlockerSettingsScreenState();
}

class _AppBlockerSettingsScreenState extends State<AppBlockerSettingsScreen> {
  static const platform = MethodChannel('com.example.mdm_client_base/device_policy');

  bool _isLoading = true;
  bool _isAccessibilityEnabled = false;
  List<AppInfo> _apps = [];
  final Set<String> _blockedApps = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _checkAccessibilityStatus();
    await _loadBlockedApps();
    await _loadApps();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkAccessibilityStatus() async {
    try {
      final isEnabled = await platform.invokeMethod('isAccessibilityServiceEnabled');
      if (mounted) {
        setState(() {
          _isAccessibilityEnabled = isEnabled;
        });
      }
    } catch (e) {
      debugPrint("Erro ao verificar acessibilidade: $e");
    }
  }

  Future<void> _loadApps() async {
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(
        true, // includeSystemApps
        true, // includeAppIcons
      );
      debugPrint("Total de aplicativos encontrados (installed_apps): ${apps.length}");
      for (var app in apps) {
        debugPrint("App: ${app.name} (${app.packageName})");
      }
      final hasSettingsApp = apps.any((app) => app.packageName == 'com.android.settings');
      if (!hasSettingsApp) {
        debugPrint("com.android.settings não encontrado, adicionando manualmente");
        apps.add(AppInfo(
          name: "Configurações do Sistema",
          packageName: "com.android.settings",
          icon: null,
          versionName: "N/A",
          versionCode: 0,
          builtWith: BuiltWith.flutter, // Use o enum BuiltWith correto
          installedTimestamp: 0,
        ));
      }
      debugPrint("com.android.settings está na lista final: ${apps.any((app) => app.packageName == 'com.android.settings')}");
      apps.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      if (mounted) {
        setState(() {
          _apps = apps;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar aplicativos: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar aplicativos: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = prefs.getStringList('blocked_apps') ?? [];
    if (mounted) {
      setState(() {
        _blockedApps.clear();
        _blockedApps.addAll(blockedList);
      });
    }
  }

  Future<void> _saveAndApplyBlockList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blocked_apps', _blockedApps.toList());
      await platform.invokeMethod('updateBlockList', {'packages': _blockedApps.toList()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lista de bloqueio aplicada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Erro ao aplicar lista de bloqueio: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aplicar lista: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onAppToggle(AppInfo app, bool isBlocked) {
    setState(() {
      if (isBlocked) {
        _blockedApps.add(app.packageName!);
      } else {
        _blockedApps.remove(app.packageName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bloqueio de Aplicativos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAndApplyBlockList,
            tooltip: 'Salvar e Aplicar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildAccessibilityCard(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _apps.length,
                    itemBuilder: (context, index) {
                      final app = _apps[index];
                      if (app.packageName == 'com.example.mdm_client_base') {
                        return const SizedBox.shrink();
                      }
                      return _buildAppListItem(app);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAccessibilityCard() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      color: _isAccessibilityEnabled ? Colors.green.shade50 : Colors.red.shade50,
      child: ListTile(
        leading: Icon(
          _isAccessibilityEnabled ? Icons.check_circle : Icons.error,
          color: _isAccessibilityEnabled ? Colors.green : Colors.red,
        ),
        title: Text(
          'Serviço de Acessibilidade',
          style: TextStyle(fontWeight: FontWeight.bold, color: _isAccessibilityEnabled ? Colors.green.shade800 : Colors.red.shade800),
        ),
        subtitle: Text(_isAccessibilityEnabled ? 'Ativo' : 'Inativo - Toque para ativar'),
        onTap: () async {
          if (!_isAccessibilityEnabled) {
            await platform.invokeMethod('openAccessibilitySettings');
          }
        },
      ),
    );
  }

  Widget _buildAppListItem(AppInfo app) {
    final icon = app.icon != null ? Image.memory(app.icon!, width: 40, height: 40) : const Icon(Icons.apps);

    return SwitchListTile(
      secondary: icon,
      title: Text(app.name ?? 'App desconhecido'),
      subtitle: Text(app.packageName ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      value: _blockedApps.contains(app.packageName),
      onChanged: (isBlocked) => _onAppToggle(app, isBlocked),
    );
  }
}
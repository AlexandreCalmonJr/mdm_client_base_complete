import 'package:flutter/material.dart';
import 'package:mdm_client_base/main.dart';
import 'package:provider/provider.dart';

class ImprovedHomeScreen extends StatefulWidget {
  const ImprovedHomeScreen({super.key});

  @override
  State<ImprovedHomeScreen> createState() => _ImprovedHomeScreenState();
}

// INÍCIO DA CORREÇÃO: Adiciona o WidgetsBindingObserver
class _ImprovedHomeScreenState extends State<ImprovedHomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
// FIM DA CORREÇÃO

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // INÍCIO DA CORREÇÃO: Regista o observador do ciclo de vida
    WidgetsBinding.instance.addObserver(this);
    // FIM DA CORREÇÃO
    
    _setupAnimations();
    Provider.of<DeviceService>(context, listen: false).initialize();
  }

  @override
  void dispose() {
    // INÍCIO DA CORREÇÃO: Remove o observador para evitar fugas de memória
    WidgetsBinding.instance.removeObserver(this);
    // FIM DA CORREÇÃO
    _animationController.dispose();
    super.dispose();
  }

  // INÍCIO DA CORREÇÃO: Este método é chamado sempre que o estado da aplicação muda (ex: volta para o primeiro plano)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Se a aplicação foi resumida (voltou a ficar visível)
    if (state == AppLifecycleState.resumed) {
      // Pede ao DeviceService para verificar novamente o status de administrador
      Provider.of<DeviceService>(context, listen: false).initialize();
    }
  }
  // FIM DA CORREÇÃO

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colorScheme.primary.withOpacity(0.05), colorScheme.surface],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Consumer<DeviceService>(
                builder: (context, deviceService, child) {
                  return CustomScrollView(
                    slivers: [
                      _buildAppBar(context, deviceService),
                      SliverPadding(
                        padding: const EdgeInsets.all(16.0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildStatusDashboard(context, deviceService),
                            const SizedBox(height: 24),
                            _buildQuickActions(context, deviceService),
                            const SizedBox(height: 24),
                            _buildMenuGrid(context),
                          ]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, DeviceService deviceService) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        title: Text('MDM Client', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        centerTitle: true,
      ),
      actions: [
        IconButton(
          icon: Icon(
            deviceService.isConnected ? Icons.cloud_done : Icons.cloud_off,
            color: deviceService.isConnected ? Colors.green : Colors.red,
          ),
          tooltip: deviceService.isConnected ? 'Online' : 'Offline',
          onPressed: () {},
        ),
        PopupMenuButton<String>(
          onSelected: (value) => _handleMenuAction(context, value),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'refresh', child: Text('Atualizar')),
            const PopupMenuItem(value: 'settings', child: Text('Configurações')),
            const PopupMenuItem(value: 'logout', child: Text('Sair')),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusDashboard(BuildContext context, DeviceService deviceService) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status do Dispositivo', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatusItem('Status', deviceService.isAdmin ? 'Administrador' : 'Sem Permissões', Icons.verified_user, deviceService.isAdmin ? Colors.green : Colors.orange),
                _buildStatusItem('Última Sincronização', _formatLastSync(deviceService.lastSync), Icons.sync, Colors.blue),
              ],
            ),
            const SizedBox(height: 16),
            _buildBatteryStatus(context, deviceService),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildBatteryStatus(BuildContext context, DeviceService deviceService) {
    final batteryColor = deviceService.batteryLevel > 50 ? Colors.green : (deviceService.batteryLevel > 20 ? Colors.orange : Colors.red);
    return Row(
      children: [
        Icon(Icons.battery_std, color: batteryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bateria', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: deviceService.batteryLevel / 100.0,
                backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation(batteryColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text('${deviceService.batteryLevel}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, DeviceService deviceService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildQuickActionButton('Bloquear', Icons.lock, Colors.red, () => deviceService.restrictSettings(true)),
            _buildQuickActionButton('Desbloquear', Icons.lock_open, Colors.green, () => deviceService.restrictSettings(false)),
            _buildQuickActionButton('Sincronizar', Icons.sync, Colors.blue, () => deviceService.sendDeviceData()),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
          child: IconButton(icon: Icon(icon, color: color), onPressed: onPressed, tooltip: label),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildMenuGrid(BuildContext context) {
    final menuItems = [
      MenuItemData(title: 'Status', icon: Icons.verified_user, route: '/provisioning_status'),
      MenuItemData(title: 'APKs', icon: Icons.install_mobile, route: '/apk_manager'),
      MenuItemData(title: 'Configurações', icon: Icons.settings, route: '/settings'),
      MenuItemData(title: 'Bloquear Apps', icon: Icons.lock, route: '/app_blocker'),
      MenuItemData(title: 'Relatórios', icon: Icons.analytics, route: '/reports'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: menuItems.length,
      itemBuilder: (context, index) {
        final item = menuItems[index];
        return Card(
          elevation: 2,
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, item.route),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    final deviceService = Provider.of<DeviceService>(context, listen: false);
    switch (action) {
      case 'refresh':
        deviceService.initialize();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados atualizados.')));
        break;
      case 'settings':
        Navigator.pushNamed(context, '/settings');
        break;
      case 'logout':
        deviceService.logout();
        Navigator.pushReplacementNamed(context, '/');
        break;
    }
  }

  String _formatLastSync(DateTime lastSync) {
    final difference = DateTime.now().difference(lastSync);
    if (difference.inMinutes < 1) return 'Agora';
    if (difference.inMinutes < 60) return '${difference.inMinutes}min atrás';
    if (difference.inHours < 24) return '${difference.inHours}h atrás';
    return '${difference.inDays}d atrás';
  }
}

class MenuItemData {
  final String title;
  final IconData icon;
  final String route;
  MenuItemData({required this.title, required this.icon, required this.route});
}

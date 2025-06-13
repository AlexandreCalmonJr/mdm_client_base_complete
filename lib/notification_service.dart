import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final Logger _logger = Logger('NotificationService');
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  NotificationService._internal();

  static NotificationService get instance => _instance;

  Future<void> initialize() async {
    // Use '@mipmap/ic_launcher' ou null para usar o ícone padrão
    const androidInitialize = AndroidInitializationSettings('ic_notification');
    const settings = InitializationSettings(
      android: androidInitialize,
    );
    
    try {
      await _flutterLocalNotificationsPlugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
          final payload = notificationResponse.payload;
          _logger.info('Notificação selecionada: $payload');
        },
      );
      _logger.info('NotificationService inicializado');
    } catch (e) {
      _logger.severe('Erro ao inicializar NotificationService: $e');
      // Tenta inicializar sem ícone personalizado
      await _initializeWithoutIcon();
    }
  }

  Future<void> _initializeWithoutIcon() async {
    try {
      // Usa um ícone padrão do Android
      const androidInitialize = AndroidInitializationSettings('@android:drawable/ic_dialog_info');
      const settings = InitializationSettings(
        android: androidInitialize,
      );
      
      await _flutterLocalNotificationsPlugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
          final payload = notificationResponse.payload;
          _logger.info('Notificação selecionada: $payload');
        },
      );
      _logger.info('NotificationService inicializado com ícone padrão do sistema');
    } catch (e) {
      _logger.severe('Erro crítico ao inicializar NotificationService: $e');
    }
  }

  Future<void> showNotification(String title, String message) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'mdm_channel',
        'MDM Notifications',
        channelDescription: 'Notificações do sistema MDM',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        // Remove o ícone personalizado para usar o padrão
        // icon: '@mipmap/ic_launcher', // removido para evitar erro
      );
      const notificationDetails = NotificationDetails(
        android: androidDetails,
      );
      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        message,
        notificationDetails,
        payload: 'Notification Payload',
      );
      _logger.info('Notificação exibida: $title - $message');
    } catch (e) {
      _logger.severe('Erro ao exibir notificação: $e');
    }
  }
}
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize(
    FlutterLocalNotificationsPlugin plugin, {
    bool pushEnabled = false,
  }) async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await plugin.initialize(settings);
  }

  static Future<void> showLocalNotification(
    RemoteMessage message,
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'teachcross_channel',
      'TeachCross Notifications',
      channelDescription: 'Notifications from TeachCross',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await plugin.show(
      0,
      message.notification?.title ?? 'TeachCross',
      message.notification?.body ?? 'You have a new notification',
      details,
    );
  }

  static void Function(String payload)? onNavigate;

  static String? consumePendingNavigation() {
    return null;
  }
}
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages FCM token registration, notification channels, and local display
class NotificationService {
  static const String _channelMessages = 'messages';
  static const String _channelAnnouncements = 'announcements';
  static const String _channelAlerts = 'priority_alerts';
  static const String _channelAdmin = 'admin_alerts';

  static Future<void> initialize(
    FlutterLocalNotificationsPlugin localNotifications, {
    bool pushEnabled = true,
  }) async {
    // Create Android notification channels
    final androidPlugin = AndroidFlutterLocalNotificationsPlugin();
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelMessages,
        'Messages',
        description: 'Teacher and support messages',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelAnnouncements,
        'Announcements',
        description: 'School and class announcements',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelAlerts,
        'Priority Alerts',
        description: 'Urgent school safety and priority alerts',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('alert'),
        enableVibration: true,
        enableLights: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelAdmin,
        'Administrative Alerts',
        description: 'Account and security notifications',
        importance: Importance.high,
      ),
    );

    // Initialize local notifications plugin
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permission
    if (!pushEnabled) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
    );

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((message) async {
      await showLocalNotification(message, localNotifications);
    });

    // Handle notification tap when app is in background (opened)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // Handle notification tap when app was terminated
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
    }
  }

  /// Register or refresh FCM token with Supabase
  static Future<void> registerToken() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token == null) return;

    // Get school_id for user
    final membership = await supabase
        .from('school_memberships')
        .select('school_id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();

    if (membership == null) return;

    await supabase.from('notification_devices').upsert({
      'user_id': user.id,
      'school_id': membership['school_id'],
      'fcm_token': token,
      'platform': 'android',
      'is_active': true,
      'last_seen_at': DateTime.now().toIso8601String(),
    }, onConflict: 'fcm_token');

    // Listen for token refresh
    messaging.onTokenRefresh.listen((newToken) async {
      await supabase.from('notification_devices').upsert({
        'user_id': user.id,
        'school_id': membership['school_id'],
        'fcm_token': newToken,
        'platform': 'android',
        'is_active': true,
      }, onConflict: 'fcm_token');
    });
  }

  /// Deactivate tokens on logout
  static Future<void> deactivateToken() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await supabase
        .from('notification_devices')
        .update({'is_active': false})
        .eq('fcm_token', token);
  }

  /// Show a local notification for foreground FCM messages
  static Future<void> showLocalNotification(
    RemoteMessage message,
    FlutterLocalNotificationsPlugin localNotifications,
  ) async {
    final notification = message.notification;
    if (notification == null) return;

    final data = message.data;
    final type = data['type'] ?? 'message';
    final channelId = type == 'alert'
        ? _channelAlerts
        : type == 'announcement'
            ? _channelAnnouncements
            : _channelMessages;

    await localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId,
          importance: type == 'alert' ? Importance.max : Importance.high,
          priority: type == 'alert' ? Priority.max : Priority.high,
          icon: '@mipmap/ic_notification',
        ),
      ),
      payload: _buildPayload(data),
    );
  }

  static String _buildPayload(Map<String, dynamic> data) {
    // Build a navigation payload — no sensitive message content
    final type = data['type'] ?? 'message';
    final conversationId = data['conversation_id'];
    final announcementId = data['announcement_id'];
    if (type == 'message' && conversationId != null) {
      return 'conversation:$conversationId';
    }
    if (type == 'announcement' && announcementId != null) {
      return 'announcement:$announcementId';
    }
    return 'home';
  }

  static void _onNotificationTap(NotificationResponse response) {
    // Navigate based on payload — handled by router
    final payload = response.payload ?? '';
    _navigateFromPayload(payload);
  }

  static void _handleNotificationOpen(RemoteMessage message) {
    final payload = _buildPayload(message.data);
    _navigateFromPayload(payload);
  }

  static void _navigateFromPayload(String payload) {
    // Navigation is handled by the router; this could trigger a
    // global navigation event via a StreamController
    // Implementation depends on the router instance in context
    // For simplicity, store payload and navigate on next frame
    _pendingNavigationPayload = payload;
  }

  static String? _pendingNavigationPayload;

  static String? consumePendingNavigation() {
    final payload = _pendingNavigationPayload;
    _pendingNavigationPayload = null;
    return payload;
  }
}

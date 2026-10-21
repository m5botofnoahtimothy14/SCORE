import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages FCM token registration, notification channels, and local display
class NotificationService {
  /// True once Firebase initialized successfully (set in main()).
  static bool available = false;

  /// Navigation sink wired by the router: payload -> route.
  static void Function(String payload)? onNavigate;

  /// Consumed at startup if a notification launched the app before the router existed.
  static String? pendingPayload;
  static const String _channelMessages = 'messages';
  static const String _channelAnnouncements = 'announcements';
  static const String _channelAlerts = 'priority_alerts';
  static const String _channelAdmin = 'admin_alerts';

  /// Value stored in `notification_devices.platform`. iOS and macOS both
  /// receive push through APNs, Android through FCM.
  static String get devicePlatform =>
      (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)
          ? 'ios'
          : 'android';

  static String get _devicePlatform => devicePlatform;

  static Future<void> initialize(
    FlutterLocalNotificationsPlugin localNotifications, {
    bool pushEnabled = true,
  }) async {
    // Notification channels are an Android concept; the plugin throws a
    // MissingPluginException on iOS, so only create them there.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = AndroidFlutterLocalNotificationsPlugin();
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelMessages,
          'Messages',
          description: 'Teacher and support messages',
          importance: Importance.high,
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
    }

    // Each platform refuses to initialize without its own settings.
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      // Permissions are requested explicitly via FirebaseMessaging below.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permission
    available = pushEnabled;
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

  /// Register or refresh FCM token with Supabase.
  ///
  /// Called at boot, after enrollment, and whenever the app returns to the
  /// foreground — a device that was retired by a failed delivery must be
  /// able to come back.
  static Future<void> registerToken() async {
    if (!available) return;
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        debugPrint('[CRIMSON] push: no signed-in user, skipping registration');
        return;
      }

      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token == null) {
        debugPrint('[CRIMSON] push: FCM returned no token');
        return;
      }

      // Get school_id for user
      final membership = await supabase
          .from('school_memberships')
          .select('school_id')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();

      if (membership == null) {
        debugPrint('[CRIMSON] push: no active membership, cannot register device');
        return;
      }

      // Register the device. The server owns the write: when the token is
      // already on file it belongs to the previous account on this handset,
      // and only the server may re-point it at the caller.
      //
      // An RPC returns its value (and throws on failure) — it does not
      // return a response object with an `error` field.
      await supabase.rpc('register_notification_device', params: {
        'p_school_id': membership['school_id'],
        'p_fcm_token': token,
        'p_platform': _devicePlatform,
      });

      debugPrint('[CRIMSON] push: device registered for ${user.id}');

      // Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) async {
        try {
          await supabase.rpc('register_notification_device', params: {
            'p_school_id': membership['school_id'],
            'p_fcm_token': newToken,
            'p_platform': _devicePlatform,
          });
        } catch (e) {
          debugPrint('[CRIMSON] push: token refresh registration failed: $e');
        }
      });
    } catch (e) {
      debugPrint('[CRIMSON] push: registration failed: $e');
    }
  }

  /// Deactivate tokens on logout
  static Future<void> deactivateToken() async {
    if (!available) return;
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      // The server owns the write: only the row that belongs to this user
      // is retired.
      await supabase.rpc('deactivate_notification_device', params: {
        'p_fcm_token': token,
      });
    } catch (_) {}
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
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
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
    final handler = onNavigate;
    if (handler != null) {
      handler(payload);
    } else {
      pendingPayload = payload;
    }
  }

  static String? consumePendingNavigation() {
    final payload = pendingPayload;
    pendingPayload = null;
    return payload;
  }
}

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static bool _pushEnabled = false;
  static String? _pendingNavigation;
  static String? _registeredToken;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;

  static Future<void> initialize(
    FlutterLocalNotificationsPlugin plugin, {
    bool pushEnabled = false,
  }) async {
    _pushEnabled = pushEnabled;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) => _handleNavigation(response.payload),
    );

    if (!_pushEnabled) return;

    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      showLocalNotification(message, plugin);
    });
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNavigation(message.data['route']?.toString());
    });

    try {
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleNavigation(initialMessage.data['route']?.toString());
      }
    } catch (error) {
      debugPrint('SCORE+ notification launch payload unavailable: $error');
    }
  }

  static Future<void> registerCurrentDevice() async {
    if (!_pushEnabled) return;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final membership = await client
          .from('school_memberships')
          .select('school_id')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .order('joined_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final schoolId = membership?['school_id'] as String?;
      if (schoolId == null || schoolId.isEmpty) return;

      final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _registerToken(client, schoolId, token);
      _registeredToken = token;

      _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        try {
          final refreshedUser = client.auth.currentUser;
          if (refreshedUser == null) return;
          final currentMembership = await client
              .from('school_memberships')
              .select('school_id')
              .eq('user_id', refreshedUser.id)
              .eq('is_active', true)
              .order('joined_at', ascending: false)
              .limit(1)
              .maybeSingle();
          final currentSchoolId = currentMembership?['school_id'] as String?;
          if (currentSchoolId == null) return;
          await _registerToken(client, currentSchoolId, newToken);
          _registeredToken = newToken;
        } catch (error) {
          debugPrint('SCORE+ could not refresh notification registration: $error');
        }
      });
    } catch (error) {
      debugPrint('SCORE+ notification registration unavailable: $error');
    }
  }

  static Future<void> _registerToken(
    SupabaseClient client,
    String schoolId,
    String token,
  ) async {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'other',
    };
    await client.rpc('register_notification_device', params: {
      'p_school_id': schoolId,
      'p_fcm_token': token,
      'p_platform': platform,
      'p_app_version': null,
    });
  }

  static Future<void> showLocalNotification(
    RemoteMessage message,
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'scoreplus_updates',
      'SCORE+ Updates',
      channelDescription: 'School notices and important account updates',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final route = message.data['route']?.toString();
    await plugin.show(
      message.messageId?.hashCode ?? message.hashCode & 0x7fffffff,
      message.notification?.title ?? 'SCORE+',
      message.notification?.body ?? 'You have a new school update.',
      details,
      payload: route,
    );
  }

  static void _handleNavigation(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final navigate = onNavigate;
    if (navigate == null) {
      _pendingNavigation = payload;
    } else {
      navigate(payload);
    }
  }

  static void Function(String payload)? onNavigate;

  static String? consumePendingNavigation() {
    final payload = _pendingNavigation;
    _pendingNavigation = null;
    return payload;
  }

  static String? get registeredToken => _registeredToken;
}

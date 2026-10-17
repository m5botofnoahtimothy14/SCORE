import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notification settings: permission status, per-channel toggles (local),
/// token registration refresh. Never claims delivery — shows truthful status.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  AuthorizationStatus? _permission;
  String? _token;
  bool _working = false;
  final Map<String, bool> _channels = {
    'messages': true,
    'announcements': true,
    'priority_alerts': true,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      token = null;
    }
    if (!mounted) return;
    setState(() {
      _permission = settings.authorizationStatus;
      _token = token;
      for (final k in _channels.keys) {
        _channels[k] = prefs.getBool('notif_$k') ?? true;
      }
    });
  }

  Future<void> _toggle(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_$key', value);
    setState(() => _channels[key] = value);
  }

  Future<void> _refreshToken() async {
    setState(() => _working = true);
    try {
      await FirebaseMessaging.instance.deleteToken();
      final token = await FirebaseMessaging.instance.getToken();
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (token != null && user != null) {
        final membership = await client
            .from('school_memberships')
            .select('school_id')
            .eq('user_id', user.id)
            .eq('is_active', true)
            .limit(1)
            .maybeSingle();
        if (membership != null) {
          await client.from('notification_devices').upsert({
            'user_id': user.id,
            'school_id': (membership as Map)['school_id'],
            'fcm_token': token,
            'platform': 'android',
            'is_active': true,
            'last_seen_at': DateTime.now().toIso8601String(),
          }, onConflict: 'fcm_token');
        }
      }
      if (mounted) {
        setState(() => _token = token);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(token == null ? 'Could not obtain a token.' : 'Push registration refreshed.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refresh failed. Check your connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _requestPermission() async {
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                _permission == AuthorizationStatus.authorized
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: const Color(0xFF1A56DB),
              ),
              title: const Text('System permission'),
              subtitle: Text(
                _permission == AuthorizationStatus.authorized
                    ? 'Allowed — alerts can appear per your system settings.'
                    : 'Not allowed — enable notifications in system settings to receive alerts.',
              ),
              trailing: _permission == AuthorizationStatus.authorized
                  ? null
                  : TextButton(onPressed: _requestPermission, child: const Text('Enable')),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Alert types', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                for (final e in _channels.entries)
                  SwitchListTile(
                    title: Text(e.key.replaceAll('_', ' ')),
                    value: e.value,
                    onChanged: (v) => _toggle(e.key, v),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    'Priority alerts use sound and vibration where your system settings allow. '
                    'The app cannot override Do Not Disturb.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.smartphone_outlined),
              title: const Text('This device'),
              subtitle: Text(_token == null
                  ? 'No push token — registration may have failed.'
                  : 'Registered for push (${_token!.substring(0, _token!.length > 12 ? 12 : _token!.length)}...)'),
              trailing: _working
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _refreshToken, child: const Text('Refresh')),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Announcements Screen')),
    );
  }
}

class AnnouncementDetailScreen extends StatelessWidget {
  final String announcementId;
  const AnnouncementDetailScreen({super.key, required this.announcementId});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Announcement Detail Screen')),
    );
  }
}

class ComposeAnnouncementScreen extends StatelessWidget {
  const ComposeAnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Compose Announcement Screen')),
    );
  }
}
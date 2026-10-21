// One row in the teachers directory.
//
// It is a separate widget (rather than inline in the screen) so the layout
// can be tested: the name, the subject and the presence line must always
// read horizontally, never squeezed into a single-character column.
import 'package:flutter/material.dart';

import '../../../core/widgets/presence_dot.dart';

/// Safe single-letter avatar initial (handles null/empty names).
String teacherInitial(dynamic value) {
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? '?' : s.substring(0, 1).toUpperCase();
}

class TeacherDirectoryRow extends StatelessWidget {
  final Map<String, dynamic> teacher;
  final bool isStudent;
  final bool opening;
  final VoidCallback? onMessage;

  const TeacherDirectoryRow({
    super.key,
    required this.teacher,
    required this.isStudent,
    required this.opening,
    required this.onMessage,
  });

  String get _name =>
      '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'.trim();

  DateTime? get _lastSeen =>
      DateTime.tryParse(teacher['last_seen_at'] as String? ?? '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFEBF5FF),
              child: Text(
                teacherInitial(teacher['first_name']),
                style: const TextStyle(
                  color: Color(0xFF1A56DB),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // The name and the presence line share one flexible column, so the
            // text always reads horizontally in the space the row leaves for
            // it — never one letter per line.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: PresenceDot(
                          lastSeen: _lastSeen,
                          labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                      if (teacher['is_leadership'] == true) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Leadership',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isStudent) ...[
              const SizedBox(width: 8),
              // A bare OutlinedButton in a Row is laid out with an unbounded
              // width, and the button's own minimum-width constraint then
              // fails the layout — which collapses the row and hides the
              // name. A zero minimum width plus a flexible wrapper keeps the
              // button inside the space the row has left.
              Flexible(
                child: OutlinedButton(
                  onPressed: opening ? null : onMessage,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: opening
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Message'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

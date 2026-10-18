// Reusable "is this teacher around right now?" indicator.
//
// The colour, the label and the online window all live here so the directory
// and the chat header can never disagree about whether someone is online.
import 'package:flutter/material.dart';

/// A teacher counts as online for three minutes after their last heartbeat.
const Duration presenceOnlineWindow = Duration(minutes: 3);

const Color presenceOnlineColor = Color(0xFF10B981);
const Color presenceOfflineColor = Color(0xFF94A3B8);

/// True when [lastSeen] is recent enough to call the teacher online.
bool isOnlineLastSeen(DateTime? lastSeen, {Duration window = presenceOnlineWindow}) {
  if (lastSeen == null) return false;
  // Future timestamps mean clock skew, not a dead client — treat as online.
  final diff = DateTime.now().difference(lastSeen.toLocal());
  return diff <= window;
}

/// "2h ago" / "5m ago" / "just now" — never negative.
String presenceRelativeTime(DateTime? lastSeen) {
  if (lastSeen == null) return '';
  final diff = DateTime.now().difference(lastSeen.toLocal());
  if (diff.isNegative || diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}

/// "Online", "Last seen 2h ago" or "Offline".
String presenceLabel(DateTime? lastSeen) {
  if (isOnlineLastSeen(lastSeen)) return 'Online';
  if (lastSeen != null) return 'Last seen ${presenceRelativeTime(lastSeen)}';
  return 'Offline';
}

Color presenceColor(DateTime? lastSeen) =>
    isOnlineLastSeen(lastSeen) ? presenceOnlineColor : presenceOfflineColor;

/// Small coloured dot plus, unless [compact], a text label.
class PresenceDot extends StatelessWidget {
  final DateTime? lastSeen;

  /// Hide the text and render the dot only (e.g. inside an app bar subtitle).
  final bool compact;

  final double dotSize;
  final TextStyle? labelStyle;

  const PresenceDot({
    super.key,
    this.lastSeen,
    this.compact = false,
    this.dotSize = 8,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final color = presenceColor(lastSeen);

    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 5, spreadRadius: 0.5),
        ],
      ),
    );

    if (compact) return dot;

    final text = Text(
      presenceLabel(lastSeen),
      style: labelStyle ??
          TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
          ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 7),
        Flexible(child: text),
      ],
    );
  }
}
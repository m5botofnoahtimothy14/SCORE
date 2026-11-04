import 'package:flutter/material.dart';
import '../design/design_system.dart';

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  const PremiumCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final widget = Container(
      padding: padding,
      decoration: BoxDecoration(color: color ?? SColor.surface, borderRadius: SRadii.lgAll, border: Border.all(color: SColor.border), boxShadow: SShadow.card),
      child: child,
    );
    if (onTap == null) return widget;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: SRadii.lgAll, onTap: onTap, child: widget));
  }
}

class PremiumPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final Widget child;
  final bool fullWidth;
  final double? height;
  const PremiumPrimaryButton({super.key, required this.onPressed, this.loading = false, required this.child, this.fullWidth = true, this.height});

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: SColor.electricBlue, foregroundColor: SColor.textInverse, elevation: 0,
        shadowColor: Colors.transparent, padding: EdgeInsets.symmetric(vertical: height ?? SSpace.md),
        shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll)),
      child: loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SColor.textInverse)) : child,
    );
    if (fullWidth) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

class PremiumSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  const PremiumSecondaryButton({super.key, required this.onPressed, required this.child});
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(foregroundColor: SColor.electricBlue, side: const BorderSide(color: SColor.electricBlue, width: 1.5),
      padding: const EdgeInsets.symmetric(vertical: SSpace.md), shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll)),
    child: child,
  );
}

class PremiumTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  const PremiumTextButton({super.key, required this.onPressed, required this.child});
  @override
  Widget build(BuildContext context) => TextButton(onPressed: onPressed, style: TextButton.styleFrom(foregroundColor: SColor.secondaryText,
    shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll)), child: child);
}

class PremiumInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label; final String? hint; final String? errorText; final bool obscureText;
  final int? maxLines; final TextInputType? keyboardType; final String? Function(String?)? validator; final ValueChanged<String>? onChanged; final ValueChanged<String>? onSubmitted;
  const PremiumInput({super.key, this.controller, this.label, this.hint, this.errorText, this.obscureText = false, this.maxLines = 1, this.keyboardType, this.validator, this.onChanged, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null && label!.isNotEmpty) ...[
        Text(label!, style: STextStyle.labelMedium.copyWith(color: SColor.secondaryText)),
        const SizedBox(height: SSpace.xs),
      ],
      TextFormField(
        controller: controller, obscureText: obscureText, maxLines: maxLines, keyboardType: keyboardType,
        validator: validator, onChanged: onChanged, onFieldSubmitted: onSubmitted,
        style: const TextStyle(color: SColor.primaryText, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint, filled: true, fillColor: SColor.surface, contentPadding: const EdgeInsets.symmetric(horizontal: SSpace.md, vertical: SSpace.md),
          isDense: true, errorText: errorText,
          border: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.border)),
          enabledBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.border)),
          focusedBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.electricBlue, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.error)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.error, width: 1.5)),
          hintStyle: const TextStyle(color: SColor.textMuted, fontSize: 14),
        ),
      ),
    ]);
  }
}

class PremiumDropdown<T> extends StatelessWidget {
  final String? label; final T? value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?>? onChanged; final String? errorText;
  const PremiumDropdown({super.key, this.label, required this.value, required this.items, this.onChanged, this.errorText});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null && label!.isNotEmpty) ...[
        Text(label!, style: STextStyle.labelMedium.copyWith(color: SColor.secondaryText)),
        const SizedBox(height: SSpace.xs),
      ],
      DropdownButtonFormField<T>(
        value: value, items: items, onChanged: onChanged, decoration: InputDecoration(
          filled: true, fillColor: SColor.surface, contentPadding: const EdgeInsets.symmetric(horizontal: SSpace.md, vertical: SSpace.md),
          isDense: true, errorText: errorText,
          border: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.border)),
          enabledBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.border)),
          focusedBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.electricBlue, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.error)),
          hintStyle: const TextStyle(color: SColor.textMuted, fontSize: 14),
        ),
      ),
    ]);
  }
}

class PremiumStatusBadge extends StatelessWidget {
  final String label; final Color color;
  const PremiumStatusBadge({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.4))),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
  );
}

class PremiumSkeleton extends StatelessWidget {
  final double width; final double height; final BorderRadius? borderRadius;
  const PremiumSkeleton({super.key, required this.width, required this.height, this.borderRadius});
  @override
  Widget build(BuildContext context) => Container(width: width, height: height, decoration: BoxDecoration(color: SColor.surfaceSoft, borderRadius: borderRadius ?? SRadii.mdAll));
}

class PremiumSectionHeader extends StatelessWidget {
  final String title; final String? actionLabel; final VoidCallback? onAction;
  const PremiumSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: STextStyle.headingSmall.copyWith(fontWeight: FontWeight.w800, color: SColor.primaryText)),
    const Spacer(),
    if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!, style: const TextStyle(color: SColor.electricBlue, fontWeight: FontWeight.w700, fontSize: 12))),
  ]);
}

class PremiumMessageBubble extends StatelessWidget {
  final String body; final bool isMine; final DateTime? createdAt; final bool read; final String? attachmentUrl;
  const PremiumMessageBubble({super.key, required this.body, required this.isMine, this.createdAt, this.read = false, this.attachmentUrl});
  @override
  Widget build(BuildContext context) {
    final alignment = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: alignment, children: [
      Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82), decoration: BoxDecoration(
        color: isMine ? SColor.electricBlue : SColor.surface,
        borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
          bottomLeft: isMine ? const Radius.circular(16) : Radius.zero, bottomRight: isMine ? Radius.zero : const Radius.circular(16)),
        border: isMine ? null : Border.all(color: SColor.border)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (body.isNotEmpty) Text(body, style: TextStyle(fontSize: 14, color: isMine ? SColor.textInverse : SColor.primaryText, height: 1.5)),
          if (attachmentUrl != null && attachmentUrl!.isNotEmpty) ...[
            const SizedBox(height: 10), ClipRRect(borderRadius: SRadii.mdAll, child: Image.network(attachmentUrl!, width: 160, height: 120, fit: BoxFit.cover)),
          ],
          const SizedBox(height: 8), Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_formatTime(createdAt), style: TextStyle(fontSize: 10, color: isMine ? SColor.textInverse.withValues(alpha: 0.75) : SColor.textMuted)),
            if (!isMine && read) ...[const SizedBox(width: 6), const Icon(Icons.done_all, size: 12, color: SColor.success)],
          ]),
        ])),
    ]));
  }
  String _formatTime(DateTime? t) { if (t == null) return ''; final d = DateTime.now().difference(t); if (d.inDays == 0) return '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}'; return '${t.day}/${t.month}'; }
}

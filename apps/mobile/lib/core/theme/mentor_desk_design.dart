// SCORE+ Design System — Glossy, modern, professional.
//
// A cohesive visual language for the Mentor Desk:
//   • Soft glassmorphism cards with bloom lighting
//   • Glossy gradient buttons with top sheen
//   • Refined typography and generous whitespace
//   • Subtle shadows, border-radius 24px+, smooth motion
//   • Per-tier accent colors carried through every surface
import 'package:flutter/material.dart';

// ── Palette ─────────────────────────────────────────────────────────
class MDColors {
  // Deep brand
  static const brandDeep = Color(0xFF0E1A3B);
  static const brand = Color(0xFF2563EB);
  static const brandLight = Color(0xFF3B82F6);

  // Tier accents
  static const studentStart = Color(0xFF2563EB);
  static const studentEnd = Color(0xFF1D4ED8);
  static const teacherStart = Color(0xFF14B8A6);
  static const teacherEnd = Color(0xFF0F766E);
  static const sltStart = Color(0xFF8B5CF6);
  static const sltEnd = Color(0xFF6D28D9);

  // Semantic
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF0284C7);

  // Ink
  static const ink950 = Color(0xFF0B1120);
  static const ink900 = Color(0xFF0F172A);
  static const ink800 = Color(0xFF1E293B);
  static const ink700 = Color(0xFF334155);
  static const ink600 = Color(0xFF475569);
  static const ink500 = Color(0xFF64748B);
  static const ink400 = Color(0xFF94A3B8);
  static const ink300 = Color(0xFFCBD5E1);
  static const ink200 = Color(0xFFE2E8F0);
  static const ink100 = Color(0xFFF1F5F9);
  static const ink50 = Color(0xFFF8FAFC);

  static const paper = Color(0xFFFFFFFF);
  static const shadow = Color(0xFF000000);
}

/// Per-tier glossy theme.
class MDTier {
  final Color start;
  final Color end;
  static const student = MDTier(start: MDColors.studentStart, end: MDColors.studentEnd);
  static const teacher = MDTier(start: MDColors.teacherStart, end: MDColors.teacherEnd);
  static const slt = MDTier(start: MDColors.sltStart, end: MDColors.sltEnd);

  const MDTier({required this.start, required this.end});

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      );
  Color get solid => start;
  Color get soft => start.withValues(alpha: 0.14);
  Color get onSoft => start;
}

// ── Spacing / radius ────────────────────────────────────────────────
const double kRadius = 24.0;
const double kRadiusSm = 16.0;
const double kRadiusLg = 32.0;
const double kGutter = 20.0;

// ── Reusable glossy components ─────────────────────────────────────

/// Glass card: frosted surface with a subtle bloom and hairline border.
class MDGlossCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Border? border;
  final List<BoxShadow>? shadow;
  final bool animate;

  const MDGlossCard({
    super.key,
    required this.child,
    this.color,
    this.radius = kRadius,
    this.padding = const EdgeInsets.all(kGutter),
    this.border,
    this.shadow,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? MDColors.paper.withValues(alpha: 0.92);
    final bg = animate
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            decoration: _decoration(baseColor),
            child: Padding(padding: padding, child: child),
          )
        : Container(
            decoration: _decoration(baseColor),
            child: Padding(padding: padding, child: child),
          );
    return bg;
  }

  BoxDecoration _decoration(Color c) => BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: MDColors.ink200.withValues(alpha: 0.18)),
        boxShadow: shadow ??
            [
              BoxShadow(
                color: MDColors.shadow.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: MDColors.brand.withValues(alpha: 0.10),
                blurRadius: 40,
                offset: const Offset(0, -8),
              ),
            ],
      );

  Color startColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
}

/// Glossy gradient button with top sheen.
class MDGlossButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool loading;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final double height;

  const MDGlossButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.loading = false,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grad = LinearGradient(
      colors: [backgroundColor ?? scheme.primary, backgroundColor ?? scheme.primary.withValues(alpha: 0.85)],
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadiusSm),
        gradient: loading ? null : grad,
        color: loading ? scheme.primary.withValues(alpha: 0.5) : null,
        boxShadow: loading
            ? null
            : [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kRadiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusSm),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            height: height,
            padding: padding,
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : child,
          ),
        ),
      ),
    );
  }
}

/// Glossy outlined button.
class MDGlossOutlineButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color? borderColor;
  final Color? foregroundColor;

  const MDGlossOutlineButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.borderColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor ?? scheme.primary,
        side: BorderSide(color: borderColor ?? scheme.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSm)),
        elevation: 0,
        backgroundColor: scheme.primary.withValues(alpha: 0.04),
      ),
      child: child,
    );
  }
}

/// Glossy input field.
class MDGlossInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  const MDGlossInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hasError ? MDColors.danger : MDColors.ink600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: MDColors.ink50.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(
              color: hasError
                  ? MDColors.danger.withValues(alpha: 0.6)
                  : scheme.primary.withValues(alpha: 0.15),
              width: 1.2,
            ),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            maxLines: maxLines ?? 1,
            enabled: enabled,
            onChanged: onChanged,
            validator: validator,
            style: const TextStyle(fontSize: 15, color: MDColors.ink900),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: MDColors.ink400.withValues(alpha: 0.7)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              errorText: errorText,
              errorStyle: const TextStyle(fontSize: 11, color: MDColors.danger),
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Glossy chip / badge.
class MDChip extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;
  final double? height;
  final double fontSize;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  const MDChip({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.height = 28,
    this.fontSize = 11,
    this.selected = false,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? MDColors.ink100;
    final bg = selected ? c : c.withValues(alpha: 0.15);
    final fg = selected ? Colors.white : (textColor ?? c);
    final child = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: selected ? 1 : 0.35), width: 1),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: fg,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
    if (onSelected == null) return child;
    return GestureDetector(onTap: () => onSelected!(!selected), child: child);
  }
}

/// Section header with glossy eyebrow + title.
class MDSectionHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MDSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.action,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kGutter / 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: MDColors.ink400,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: MDColors.ink900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          if (action != null) action! else if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Glossy metric tile.
class MDMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final MDTier tier;
  final VoidCallback? onTap;

  const MDMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.tier,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusSm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(kGutter),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(color: scheme.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: tier.gradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: tier.solid.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Icon(icon, size: 17, color: Colors.white),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 18, color: MDColors.ink400),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: MDColors.ink900,
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MDColors.ink600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(fontSize: 11, color: MDColors.ink400),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft bloom background for hero headers.
class MDBloom extends StatelessWidget {
  final Color color;
  final double size;
  final Alignment alignment;

  const MDBloom({
    super.key,
    required this.color,
    this.size = 220,
    this.alignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}

/// Glossy section card header for list items.
class MDListCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const MDListCard({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: kGutter, vertical: 14)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.08)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

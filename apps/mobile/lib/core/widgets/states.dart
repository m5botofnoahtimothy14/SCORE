import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: AppColors.ink700)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyView({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 64, color: AppColors.ink300),
            const SizedBox(height: 16),
          ],
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink900)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: TextStyle(fontSize: 14, color: AppColors.ink500)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class MDSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MDSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink700,
            letterSpacing: 0.5,
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                color: AppColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class MDMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final MDTier tier;
  final VoidCallback? onTap;

  const MDMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tier,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kGutter),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: AppColors.ink200),
        boxShadow: [
          BoxShadow(
            color: tier.solid.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tier.solid),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.ink900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.ink500,
            ),
          ),
        ],
      ),
    );
  }
}

class MDListCard extends StatelessWidget {
  final Widget child;

  const MDListCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: AppColors.ink200),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MDGlossButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool loading;
  final double? height;
  final double? width;

  const MDGlossButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.loading = false,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? 56,
      width: width,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSm)),
          elevation: 4,
          shadowColor: AppColors.brand.withValues(alpha: 0.35),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : child,
        ),
    );
  }
}

class MDGlossOutlineButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool loading;

  const MDGlossOutlineButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: BorderSide(color: AppColors.brand, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSm)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brand,
                ),
              )
            : child,
        ),
    );
  }
}

class MDGlossInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final int? maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  const MDGlossInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.ink900,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: AppColors.ink300,
            ),
            errorText: errorText,
            errorStyle: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
            ),
            filled: true,
            fillColor: AppColors.surfaceCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSm),
              borderSide: BorderSide(color: AppColors.ink300.withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSm),
              borderSide: BorderSide(color: AppColors.ink300.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSm),
              borderSide: BorderSide(color: AppColors.brand, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSm),
              borderSide: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSm),
              borderSide: BorderSide(color: AppColors.danger, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}

class MDGlossInputOutlined extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final int? maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const MDGlossInputOutlined({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.ink900,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.ink300,
        ),
        errorText: errorText,
        errorStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.danger,
        ),
        filled: true,
        fillColor: AppColors.surfaceCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
          borderSide: BorderSide(color: AppColors.ink300.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
          borderSide: BorderSide(color: AppColors.ink300.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
          borderSide: BorderSide(color: AppColors.brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
          borderSide: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
          borderSide: BorderSide(color: AppColors.danger, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class MDButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool loading;
  final double? height;
  final bool fullWidth;

  const MDButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.loading = false,
    this.height,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? 56,
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSm)),
          elevation: 4,
          shadowColor: AppColors.brand.withValues(alpha: 0.35),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : child,
        ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/design_system.dart';
import '../../../core/widgets/premium_card.dart';
import '../../../core/widgets/premium_states.dart';

class AiManagerScreen extends StatefulWidget {
  const AiManagerScreen({super.key});

  @override
  State<AiManagerScreen> createState() => _AiManagerScreenState();
}

class _AiManagerScreenState extends State<AiManagerScreen> {
  double _textSize = 1.0;
  double _cardRadius = 16.0;
  bool _darkMode = false;
  Color _primaryColor = SColor.primary;
  bool _loading = true;

  final List<Color> _colorOptions = [
    SColor.primary,
    SColor.accent,
    SColor.success,
    SColor.leadershipTier,
    SColor.warning,
    SColor.error,
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _textSize = prefs.getDouble('ai_text_size') ?? 1.0;
      _cardRadius = prefs.getDouble('ai_card_radius') ?? 16.0;
      _darkMode = prefs.getBool('ai_dark_mode') ?? false;
      final colorValue = prefs.getInt('ai_primary_color');
      if (colorValue != null) {
        _primaryColor = Color(colorValue);
      }
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ai_text_size', _textSize);
    await prefs.setDouble('ai_card_radius', _cardRadius);
    await prefs.setBool('ai_dark_mode', _darkMode);
    await prefs.setInt('ai_primary_color', _primaryColor.value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Settings saved. Restart app to apply.'),
        backgroundColor: SColor.success,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SColor.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SColor.primaryText),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('AI Manager', style: TextStyle(color: SColor.primaryText, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const PremiumLoading()
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(SLayout.gutter(context), 16, SLayout.gutter(context), 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App Management', style: STextStyle.displayLarge.copyWith(fontSize: 26)),
                  const SizedBox(height: SSpace.sm),
                  Text('Control app UI, styling, and adjustments.',
                      style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText)),
                  const SizedBox(height: SSpace.lg),

                  // Text Size
                  PremiumCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Text Size', style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: SSpace.sm),
                        Slider(
                          value: _textSize,
                          min: 0.8,
                          max: 1.4,
                          divisions: 6,
                          label: '${(_textSize * 100).round()}%',
                          activeColor: SColor.primary,
                          onChanged: (v) => setState(() => _textSize = v),
                        ),
                        Text('Current: ${(_textSize * 100).round()}%', style: STextStyle.captionMuted),
                      ],
                    ),
                  ),
                  const SizedBox(height: SSpace.md),

                  // Card Radius
                  PremiumCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Card Corner Radius', style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: SSpace.sm),
                        Slider(
                          value: _cardRadius,
                          min: 4,
                          max: 32,
                          divisions: 7,
                          label: '${_cardRadius.round()}px',
                          activeColor: SColor.primary,
                          onChanged: (v) => setState(() => _cardRadius = v),
                        ),
                        Text('Current: ${_cardRadius.round()}px', style: STextStyle.captionMuted),
                      ],
                    ),
                  ),
                  const SizedBox(height: SSpace.md),

                  // Dark Mode
                  PremiumCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Dark Mode', style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: SSpace.xs),
                              Text('Switch between light and dark theme',
                                  style: STextStyle.captionMuted),
                            ],
                          ),
                        ),
                        Switch(
                          value: _darkMode,
                          activeColor: SColor.primary,
                          onChanged: (v) => setState(() => _darkMode = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SSpace.md),

                  // Primary Color
                  PremiumCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Primary Color', style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: SSpace.sm),
                        Wrap(
                          spacing: SSpace.sm,
                          runSpacing: SSpace.sm,
                          children: _colorOptions.map((color) {
                            final selected = _primaryColor.value == color.value;
                            return GestureDetector(
                              onTap: () => setState(() => _primaryColor = color),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: SRadii.mdAll,
                                  border: Border.all(
                                    color: selected ? SColor.primaryText : SColor.border,
                                    width: selected ? 3 : 1,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SSpace.lg),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: SSpace.md),

                  // Info
                  PremiumCard(
                    padding: const EdgeInsets.all(SSpace.md),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: SColor.info, size: 20),
                        const SizedBox(width: SSpace.sm),
                        Expanded(
                          child: Text(
                            'Changes take effect after restarting the app. These settings control the visual appearance of SCORE+.',
                            style: STextStyle.captionMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

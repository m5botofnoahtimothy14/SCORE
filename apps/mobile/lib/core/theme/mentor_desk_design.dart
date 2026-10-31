import 'package:flutter/material.dart';

import 'app_theme.dart';

// Re-export the consolidated design tokens from app_theme.dart
// This file exists for backwards compatibility with screens that import from it.
export 'app_theme.dart'
    show AppColors, MDColors, MDTier, TierAccent, kGutter, kRadiusSm, kRadiusLg, kRadiusXl;

// Compatibility aliases for code that imports MD* widgets from here
export '../widgets/states.dart'
    show LoadingView, ErrorView, EmptyView, MDSectionHeader, MDMetricTile, MDListCard,
        MDGlossButton, MDGlossOutlineButton, MDGlossInput, MDGlossInputOutlined, MDButton;
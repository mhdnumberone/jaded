// lib/presentation/providers/theme_providers.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/theme_service.dart';

// Provider for ThemeService
final themeServiceProvider = Provider<ThemeService>((ref) {
  return ThemeService(); // إنشاء instance من ThemeService
});

// StateNotifierProvider for managing theme state
final themeStateProvider =
    StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  // تمرير ThemeService إلى ThemeNotifier
  return ThemeNotifier(ref.watch(themeServiceProvider));
});

class ThemeState {
  final ThemeMode themeMode;
  final Color primaryColor;
  final bool useMaterial3;

  ThemeState({
    required this.themeMode,
    required this.primaryColor,
    required this.useMaterial3,
  });

  // يمكنك حذف dialogBackgroundColor من هنا إذا كنت ستعتمد على ألوان الثيم مباشرة
  // Color get dialogBackgroundColor =>
  //     themeMode == ThemeMode.dark ? const Color(0xFF2C2C2C) : Colors.grey[200]!;

  ThemeState copyWith({
    ThemeMode? themeMode,
    Color? primaryColor,
    bool? useMaterial3,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      primaryColor: primaryColor ?? this.primaryColor,
      useMaterial3: useMaterial3 ?? this.useMaterial3,
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  final ThemeService _themeService;
  // اللون الافتراضي يمكن أن يكون من ThemeService أيضًا إذا أردت
  // static const Color intelligencePrimaryColor = Color(0xFF004D40);

  ThemeNotifier(this._themeService) // استقبال ThemeService
      : super(ThemeState(
          themeMode: ThemeMode.system, // القيمة الافتراضية قبل التحميل
          primaryColor: ThemeService
              .intelligencePrimaryColor, // استخدام اللون الافتراضي من ThemeService
          useMaterial3: true, // القيمة الافتراضية قبل التحميل
        )) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final themeMode = await _themeService.loadThemeMode();
    // استخدام دالة loadPrimaryColor من ThemeService التي توفر اللون الافتراضي
    final primaryColor = await _themeService.loadPrimaryColor();
    final useMaterial3 = await _themeService.loadUseMaterial3();

    if (mounted) {
      state = ThemeState(
        themeMode: themeMode,
        primaryColor: primaryColor,
        useMaterial3: useMaterial3,
      );
    }
  }

  void updateThemeMode(ThemeMode mode) {
    if (mode == state.themeMode) return;
    state = state.copyWith(themeMode: mode);
    _themeService.saveThemeMode(mode);
  }

  void updatePrimaryColor(Color color) {
    if (color == state.primaryColor) return;
    state = state.copyWith(primaryColor: color);
    _themeService.savePrimaryColor(color);
  }

  void toggleMaterial3(bool useMaterial3) {
    if (useMaterial3 == state.useMaterial3) return;
    state = state.copyWith(useMaterial3: useMaterial3);
    _themeService.saveUseMaterial3(useMaterial3);
  }
}

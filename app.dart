import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'presentation/chat/providers/theme_providers.dart';
import 'presentation/home/home_page.dart';

// اسم التطبيق الذي سنستخدمه في العرض
const String displayedAppName =
    "The Conduit"; // أو "الساتر" إذا اخترت اسمًا عربيًا

class TheConduitApp extends ConsumerWidget {
  // تم تغيير الاسم
  const TheConduitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeStateProvider);
    final primaryColor = themeState.primaryColor;
    final useMaterial3 = themeState.useMaterial3;

    final TextTheme baseTextTheme = Theme.of(context).textTheme;
    final TextTheme cairoTextTheme = GoogleFonts.cairoTextTheme(baseTextTheme);
    final TextTheme cairoTextThemeLight = cairoTextTheme.apply(
        bodyColor: Colors.black87, displayColor: Colors.black87);
    final TextTheme cairoTextThemeDark = cairoTextTheme.apply(
        bodyColor: Colors.white.withOpacity(0.87),
        displayColor: Colors.white.withOpacity(0.87));

    return MaterialApp(
      title: displayedAppName,
      themeMode: themeState.themeMode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: useMaterial3,
        primaryColor: primaryColor,
        textTheme: cairoTextThemeLight,
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          secondary: primaryColor.withOpacity(0.7),
          tertiary: primaryColor.withOpacity(0.3),
          surface: Colors.grey[50]!, // لون خلفية Scaffold
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.black87,
          error: Colors.redAccent,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: useMaterial3 ? 0 : 2,
          centerTitle: true,
          titleTextStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          shape: useMaterial3
              ? null
              : const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: GoogleFonts.cairo(
                textStyle: baseTextTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
          hintStyle: GoogleFonts.cairo(
              textStyle:
                  baseTextTheme.bodyMedium?.copyWith(color: Colors.grey[400])),
        ),
        cardTheme: CardTheme(
          elevation: useMaterial3 ? 1 : 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          color: useMaterial3 ? Colors.grey[50] : Colors.white,
        ),
        tabBarTheme: TabBarTheme(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          unselectedLabelStyle:
              GoogleFonts.cairo(textStyle: baseTextTheme.labelLarge),
          indicator: useMaterial3
              ? const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: Colors.white, width: 2.5)),
                )
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withOpacity(0.2),
                ),
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        dialogTheme: DialogTheme(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          titleTextStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          contentTextStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.bodyMedium
                  ?.copyWith(fontSize: 14, color: Colors.black54)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          modalBackgroundColor: Colors.white, // لخلفية الـ ModalBottomSheet
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: useMaterial3,
        primaryColor: primaryColor,
        brightness: Brightness.dark,
        textTheme: cairoTextThemeDark,
        colorScheme: ColorScheme.dark(
          primary: primaryColor,
          secondary: primaryColor.withOpacity(0.7),
          tertiary: primaryColor.withOpacity(0.3),
          surface: const Color(0xFF1A1A1A), // لون خلفية Scaffold
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white.withOpacity(0.87),
          error: Colors.redAccent[100]!,
          onError: Colors.black,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: AppBarTheme(
          backgroundColor: useMaterial3
              ? const Color(0xFF1A1A1A) // لون أغمق قليلاً لـ M3 Dark
              : primaryColor.withOpacity(0.9),
          foregroundColor: Colors.white.withOpacity(0.9),
          elevation: useMaterial3 ? 0 : 2,
          centerTitle: true,
          titleTextStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9))),
          shape: useMaterial3
              ? null
              : const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: GoogleFonts.cairo(
                textStyle: baseTextTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[700]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[700]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
          hintStyle: GoogleFonts.cairo(
              textStyle:
                  baseTextTheme.bodyMedium?.copyWith(color: Colors.grey[500])),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF252525),
          elevation: useMaterial3 ? 1 : 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
        ),
        tabBarTheme: TabBarTheme(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          unselectedLabelStyle:
              GoogleFonts.cairo(textStyle: baseTextTheme.labelLarge),
          indicator: useMaterial3
              ? BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: primaryColor, width: 2.5)),
                )
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withOpacity(0.15),
                ),
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        dialogTheme: DialogTheme(
          backgroundColor: const Color(0xFF2C2C2C),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          titleTextStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.87))),
          contentTextStyle: GoogleFonts.cairo(
              textStyle: baseTextTheme.bodyMedium?.copyWith(
                  fontSize: 14, color: Colors.white.withOpacity(0.7))),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF2C2C2C),
          modalBackgroundColor: Color(0xFF2C2C2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

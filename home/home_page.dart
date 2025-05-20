// lib/presentation/home/home_page.dart - Updated with Control Tab
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart' show displayedAppName;
import '../../core/logging/logger_provider.dart';
import '../../core/security/self_destruct_service.dart'; // Import SelfDestructService
import '../about_tab/about_tab.dart';
import '../chat/chat_list_screen.dart';
// Ensure this path is correct and auth_providers.dart exports authServiceProvider
import '../chat/providers/auth_providers.dart';
import '../chat/providers/theme_providers.dart';
import '../control_tab/control_tab.dart'; // Import the new Control Tab
import '../decoy_screen/decoy_screen.dart'; // For navigation on logout
import '../encryption_tab/encryption_screen.dart';
import '../history_tab/history_tab.dart';

final currentHomePageIndexProvider = StateProvider<int>((ref) => 1);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final List<Widget> _tabs = [
    const ChatListScreen(),
    const EncryptionScreen(),
    const HistoryTab(),
  ];

  void _onNavBarItemTapped(int index) {
    ref.read(currentHomePageIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final currentScreenIndex = ref.watch(currentHomePageIndexProvider);
    final currentTheme = Theme.of(context);
    final colorScheme = currentTheme.colorScheme;
    final agentCodeAsync = ref.watch(currentAgentCodeProvider);

    String appBarTitleText = displayedAppName;
    appBarTitleText = agentCodeAsync.when(
      data: (code) => (code != null && code.isNotEmpty)
          ? 'العميل: $code'
          : displayedAppName,
      loading: () => 'جاري التحميل...',
      error: (err, stack) => displayedAppName,
    );

    String dynamicAppBarTitle = appBarTitleText;

    return Scaffold(
      appBar: AppBar(
        title: AnimatedTextKit(
          key: ValueKey(dynamicAppBarTitle),
          animatedTexts: [
            TypewriterAnimatedText(
              dynamicAppBarTitle,
              textStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimary,
                fontFamily: GoogleFonts.cairo().fontFamily,
              ),
              speed: const Duration(milliseconds: 100),
            ),
          ],
          totalRepeatCount: 1,
          pause: const Duration(milliseconds: 1200),
          displayFullTextOnTap: true,
        ),
        backgroundColor: colorScheme.brightness == Brightness.dark
            ? const Color(0xFF1A1D21)
            : colorScheme.primary,
        elevation: 1.0,
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'تغيير المظهر',
            onPressed: () =>
                HomePageDialogs.showThemeSettingsDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'خيارات إضافية',
            onPressed: () => HomePageDialogs.showMoreOptionsBottomSheet(
                context, ref, (int newIndex) {
              // This callback might not be needed if navigation is handled within the sheet itself
            }),
          ),
        ],
      ),
      body: IndexedStack(
        index: currentScreenIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble_rounded),
            label: 'الدردشة',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.enhanced_encryption_outlined),
            activeIcon: Icon(Icons.enhanced_encryption),
            label: 'التشفير',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'السجل',
          ),
        ],
        currentIndex: currentScreenIndex,
        onTap: _onNavBarItemTapped,
        backgroundColor: colorScheme.brightness == Brightness.dark
            ? const Color(0xFF16181A)
            : Colors.white,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.brightness == Brightness.dark
            ? Colors.grey[400]
            : Colors.grey[600],
        selectedLabelStyle:
            GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12.5),
        unselectedLabelStyle: GoogleFonts.cairo(fontSize: 12),
        type: BottomNavigationBarType.fixed,
        elevation: 8.0,
      ),
    );
  }
}

class HomePageDialogs {
  static Future<void> _triggerActualSelfDestruct(
      BuildContext context, WidgetRef ref) async {
    final logger = ref.read(appLoggerProvider);
    logger.error(
        "SELF-DESTRUCT SEQUENCE INITIATED FROM MENU.", "MENU OPTION ACTIVATED");

    // Capture mounted state before first async gap
    bool isMounted = context.mounted;
    if (!isMounted) {
      logger.warn("SelfDestructMenu",
          "Attempting to show confirmation dialog, but context is unmounted.");
      return;
    }

    final bool? confirmDestruct = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(dialogCtx).colorScheme.surface,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('تأكيد التدمير النهائي',
                style: GoogleFonts.cairo(
                    color: Colors.red.shade700, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Icon(Icons.warning_amber_rounded,
                color: Colors.red.shade700, size: 28),
          ],
        ),
        content: Text(
          'هل أنت متأكد أنك تريد تدمير جميع المحادثات والسجلات بشكل نهائي؟ هذا الإجراء لا يمكن التراجع عنه وسيتم تسجيل خروجك.',
          textAlign: TextAlign.right,
          style: GoogleFonts.cairo(fontSize: 15),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('إلغاء',
                style: GoogleFonts.cairo(
                    color: Theme.of(dialogCtx).textTheme.bodyLarge?.color)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: Text('تدمير نهائي',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
          ),
        ],
      ),
    );

    // Re-check mounted state after async gap (showDialog)
    isMounted = context.mounted;

    if (confirmDestruct == true) {
      if (isMounted) {
        // selfDestructServiceProvider.initiateSelfDestruct will handle its own context checks
        await ref
            .read(selfDestructServiceProvider)
            .initiateSelfDestruct(context, triggeredBy: "HomePageMenu");
      } else {
        logger.warn("SelfDestructMenu",
            "Context was unmounted after confirmation dialog before self-destruct service call.");
      }
    } else {
      logger.info(
          "SelfDestructMenu", "Self-destruct cancelled by user from menu.");
    }
  }

  static void showThemeSettingsDialog(BuildContext context, WidgetRef ref) {
    final themeNotifier = ref.read(themeStateProvider.notifier);
    Color pickerColor = ref.read(themeStateProvider).primaryColor;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          title: Text('إعدادات المظهر', style: GoogleFonts.cairo()),
          contentPadding: const EdgeInsets.all(16),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              final currentThemeStateForDialog = ref.watch(themeStateProvider);
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('وضع التطبيق',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    RadioListTile<ThemeMode>(
                      title: Text('فاتح', style: GoogleFonts.cairo()),
                      value: ThemeMode.light,
                      groupValue: currentThemeStateForDialog.themeMode,
                      onChanged: (v) => setDialogState(
                          () => themeNotifier.updateThemeMode(v!)),
                      activeColor: currentThemeStateForDialog.primaryColor,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('داكن', style: GoogleFonts.cairo()),
                      value: ThemeMode.dark,
                      groupValue: currentThemeStateForDialog.themeMode,
                      onChanged: (v) => setDialogState(
                          () => themeNotifier.updateThemeMode(v!)),
                      activeColor: currentThemeStateForDialog.primaryColor,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('نظام', style: GoogleFonts.cairo()),
                      value: ThemeMode.system,
                      groupValue: currentThemeStateForDialog.themeMode,
                      onChanged: (v) => setDialogState(
                          () => themeNotifier.updateThemeMode(v!)),
                      activeColor: currentThemeStateForDialog.primaryColor,
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('استخدام Material 3',
                            style:
                                GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        Switch(
                          value: currentThemeStateForDialog.useMaterial3,
                          onChanged: (v) => setDialogState(
                              () => themeNotifier.toggleMaterial3(v)),
                          activeColor: currentThemeStateForDialog.primaryColor,
                        ),
                      ],
                    ),
                    const Divider(),
                    Text('اللون الرئيسي',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ColorPicker(
                      pickerColor: pickerColor,
                      onColorChanged: (color) =>
                          setDialogState(() => pickerColor = color),
                      enableAlpha: false,
                      displayThumbColor: true,
                      labelTypes: const [],
                      pickerAreaHeightPercent: 0.4,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            TextButton(
              onPressed: () {
                themeNotifier.updatePrimaryColor(pickerColor);
                Navigator.of(dialogContext).pop();
              },
              child: Text('حفظ',
                  style: GoogleFonts.cairo(
                      color: Theme.of(dialogContext).primaryColor)),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildBottomSheetTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) =>
      ListTile(
        leading: Icon(icon,
            color: iconColor ?? Theme.of(context).primaryColor, size: 22),
        title: Text(title,
            style: GoogleFonts.cairo(fontSize: 15, color: textColor)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 20,
        onTap: onTap,
      );

  static void showMoreOptionsBottomSheet(
      BuildContext context, WidgetRef ref, Function(int) onNavigateToAbout) {
    final currentTheme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: currentTheme.bottomSheetTheme.modalBackgroundColor ??
          currentTheme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext bottomSheetContext) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 45,
                height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10)),
              ),
              _buildBottomSheetTile(
                context: bottomSheetContext,
                icon: Icons.info_outline_rounded,
                title: 'حول التطبيق',
                onTap: () {
                  bool isMountedBSCtx = bottomSheetContext.mounted;
                  bool isMountedMainCtx = context.mounted;
                  if (isMountedBSCtx) Navigator.pop(bottomSheetContext);
                  if (isMountedMainCtx)
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AboutTab()));
                },
              ),
              _buildBottomSheetTile(
                context: bottomSheetContext,
                icon: Icons.settings_applications_outlined,
                title: 'إعدادات المظهر',
                onTap: () {
                  bool isMountedBSCtx = bottomSheetContext.mounted;
                  if (isMountedBSCtx) Navigator.pop(bottomSheetContext);
                  // showThemeSettingsDialog captures context before async gap if any
                  showThemeSettingsDialog(context, ref);
                },
              ),
              _buildBottomSheetTile(
                context: bottomSheetContext,
                icon: Icons.share_outlined,
                title: 'مشاركة التطبيق',
                onTap: () {
                  bool isMountedBSCtx = bottomSheetContext.mounted;
                  if (isMountedBSCtx) Navigator.pop(bottomSheetContext);
                  const String shareText =
                      'جرب تطبيق $displayedAppName للاتصالات الآمنة.';
                  Share.share(shareText, subject: displayedAppName);
                },
              ),
              const Divider(height: 25, thickness: 0.5),
              _buildBottomSheetTile(
                context: bottomSheetContext,
                icon: Icons.delete_forever_outlined,
                title: 'تدمير نهائي للمحادثات',
                iconColor: Colors.red.shade700,
                textColor: Colors.red.shade700,
                onTap: () async {
                  bool isMountedBSCtx = bottomSheetContext.mounted;
                  bool isMountedMainCtx = context.mounted;
                  if (isMountedBSCtx) Navigator.pop(bottomSheetContext);
                  if (isMountedMainCtx) {
                    // _triggerActualSelfDestruct will handle its own context checks
                    await _triggerActualSelfDestruct(context, ref);
                  } else {
                    ref.read(appLoggerProvider).warn("SelfDestructMenuOption",
                        "Main context unmounted before triggering self-destruct.");
                  }
                },
              ),
              _buildBottomSheetTile(
                context: bottomSheetContext,
                icon: Icons.logout_rounded,
                title: 'تسجيل الخروج',
                onTap: () async {
                  bool isMountedBSCtx = bottomSheetContext.mounted;
                  bool isMountedMainCtx = context.mounted;

                  if (isMountedBSCtx) Navigator.pop(bottomSheetContext);

                  if (isMountedMainCtx) {
                    final authService = ref.read(authServiceProvider);
                    await authService.signOut(); // Async gap

                    // Re-check mounted state after async gap
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) =>
                                const DecoyScreen(isPostDestruct: false)),
                        (route) => false,
                      );
                    }
                  } else {
                    ref.read(appLoggerProvider).warn("LogoutOption",
                        "Main context unmounted before attempting logout.");
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

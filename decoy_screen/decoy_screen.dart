// lib/presentation/decoy_screen/decoy_screen.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";

import "../../app.dart";
import "../../core/logging/logger_provider.dart";
import "decoy_screen_controller.dart";

class DecoyScreen extends ConsumerWidget {
  final bool isPostDestruct;
  const DecoyScreen({super.key, this.isPostDestruct = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(decoyScreenControllerProvider.notifier);
    final state = ref.watch(decoyScreenControllerProvider);

    // عرض شاشة القفل إذا تم تجاوز الحد الأقصى للمحاولات
    if (state.lockoutEndTime != null) {
      return _buildLockoutScreen(context, controller.getRemainingLockoutTime());
    }

    // عرض شاشة ما بعد التدمير
    if (state.isPostDestruct || isPostDestruct) {
      return _buildPostDestructScreen(context);
    }

    // عرض الشاشة الرئيسية
    return GestureDetector(
      onTap: () {
        controller.handleTap();
        if (controller.shouldShowPasswordDialog()) {
          _showPasswordDialog(context, ref);
        }
      },
      child: _buildMainScreen(context, state),
    );
  }

  Widget _buildLockoutScreen(BuildContext context, String remainingTime) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 80,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 30),
              Text(
                "لا يمكنك تسجيل الدخول الآن",
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                "يرجى المحاولة مرة أخرى بعد: $remainingTime",
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostDestructScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 80,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 30),
              Text(
                "تم تفعيل وضع الأمان. النظام مقفل.",
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainScreen(BuildContext context, DecoyScreenState state) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.shield_outlined,
                size: 80,
                color: state.systemCheckComplete
                    ? theme.primaryColor
                    : Colors.grey[600],
              ),
              const SizedBox(height: 30),
              Text(
                state.statusMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: state.systemCheckComplete
                      ? Colors.green[600]
                      : theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 20),
              if (!state.systemCheckComplete)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: state.progressValue,
                      backgroundColor: Colors.grey[300],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(theme.primaryColor),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "${(state.progressValue * 100).toInt()}%",
                      style: GoogleFonts.cairo(
                          fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, WidgetRef ref) {
    final TextEditingController passwordController = TextEditingController();
    final controller = ref.read(decoyScreenControllerProvider.notifier);
    final state = ref.read(decoyScreenControllerProvider);
    final logger = ref.read(appLoggerProvider);
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor:
                  Theme.of(dialogContext).brightness == Brightness.dark
                      ? const Color(0xFF1F1F1F)
                      : Colors.grey[50],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text("الوصول المشفر",
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          color:
                              Theme.of(dialogContext).colorScheme.onSurface)),
                  const SizedBox(width: 8),
                  Icon(Icons.security_outlined,
                      color: Theme.of(dialogContext).primaryColor),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("يرجى إدخال رمز المصادقة المخصص للوصول إلى النظام.",
                      textAlign: TextAlign.right,
                      style: GoogleFonts.cairo(
                          fontSize: 14, color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  TextField(
                    controller: passwordController,
                    keyboardType: TextInputType.text,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                        fontSize: 22,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(dialogContext).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: "- - - - - -",
                      hintStyle: GoogleFonts.cairo(
                          color: Colors.grey[500], fontSize: 20),
                      border: OutlineInputBorder(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(
                            color: Theme.of(dialogContext).primaryColor,
                            width: 2),
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(dialogContext).brightness == Brightness.dark
                              ? Colors.black.withOpacity(0.1)
                              : Colors.white,
                    ),
                  ),
                  if (state.failedLoginAttempts > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Text(
                        "المحاولات الخاطئة: ${state.failedLoginAttempts}/5",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: Colors.orange.shade700),
                      ),
                    ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actionsPadding: const EdgeInsets.only(bottom: 20, top: 10),
              actions: <Widget>[
                ElevatedButton.icon(
                  icon: isLoading
                      ? Container(
                          width: 20,
                          height: 20,
                          padding: const EdgeInsets.all(2.0),
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(Icons.login_rounded, size: 20),
                  label: Text(isLoading ? "جاري التحقق..." : "تأكيد الوصول",
                      style: GoogleFonts.cairo(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 3,
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() {
                            isLoading = true;
                          });

                          final enteredAgentCode =
                              passwordController.text.trim();
                          final bool isDialogCtxMounted = dialogContext.mounted;
                          final bool isMainCtxMounted = context.mounted;

                          logger.info("DecoyPasswordDialog",
                              "محاولة تسجيل الدخول برمز الوكيل: $enteredAgentCode");

                          final authResult = await controller
                              .authenticateWithAgentCode(enteredAgentCode);

                          if (!isDialogCtxMounted || !isMainCtxMounted) {
                            return;
                          }

                          if (authResult.success) {
                            logger.info("DecoyPasswordDialog",
                                "تم التحقق بنجاح من رمز الوكيل: $enteredAgentCode");

                            if (authResult.isPanicCode) {
                              // رمز الهلع - سيتم التعامل معه في وحدة التحكم
                              Navigator.of(dialogContext).pop();
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                    builder: (_) => const TheConduitApp()),
                              );
                              return;
                            }

                            Navigator.of(dialogContext).pop();
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const TheConduitApp()),
                            );
                          } else {
                            logger.warn("DecoyPasswordDialog",
                                "رمز وكيل غير صالح: $enteredAgentCode");

                            if (ref
                                    .read(decoyScreenControllerProvider)
                                    .failedLoginAttempts >=
                                5) {
                              Navigator.of(dialogContext).pop();
                            } else {
                              ScaffoldMessenger.of(dialogContext)
                                  .showSnackBar(SnackBar(
                                content: Text(authResult.message,
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.cairo()),
                                backgroundColor: Colors.red[700],
                              ));
                              setDialogState(() {
                                isLoading = false;
                              });
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

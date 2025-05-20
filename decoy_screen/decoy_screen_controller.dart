// lib/presentation/decoy_screen/decoy_screen_controller.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/logger_provider.dart';
import '../../core/security/self_destruct_service.dart';
import '../chat/services/auth_service.dart';

class DecoyScreenController extends StateNotifier<DecoyScreenState> {
  final Ref _ref;
  final AuthService _authService;
  Timer? _progressTimer;
  Timer? _lockoutTimer;

  static const String _failedAttemptsKey = 'failed_login_attempts_conduit';
  static const String _lockoutEndTimeKey = 'lockout_end_time_conduit';
  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 30);

  DecoyScreenController(this._ref, this._authService)
      : super(DecoyScreenState.initial()) {
    _loadFailedAttempts();
    _loadLockoutTime();
    if (!state.isPostDestruct) {
      _startSystemCheckAnimation();
    }
  }

  void _startSystemCheckAnimation() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      state = state.copyWith(
        progressValue: state.progressValue + 0.02,
      );

      if (state.progressValue >= 1.0) {
        state = state.copyWith(
          progressValue: 1.0,
          statusMessage: "فحص النظام الأساسي مكتمل.",
          systemCheckComplete: true,
        );
        timer.cancel();
      } else if (state.progressValue > 0.7) {
        state = state.copyWith(
          statusMessage: "التحقق من سلامة المكونات...",
        );
      } else if (state.progressValue > 0.4) {
        state = state.copyWith(
          statusMessage: "تحميل وحدات الأمان...",
        );
      }
    });
  }

  Future<void> _loadFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      failedLoginAttempts: prefs.getInt(_failedAttemptsKey) ?? 0,
    );

    // تحقق مما إذا تم تجاوز الحد الأقصى للمحاولات
    if (state.failedLoginAttempts >= _maxFailedAttempts &&
        !state.isPostDestruct) {
      _ref.read(appLoggerProvider).warn("DecoyScreenInit",
          "Max failed attempts (${state.failedLoginAttempts}) detected on load. Triggering silent self-destruct.");
      _triggerSilentSelfDestruct(triggeredBy: "MaxFailedAttemptsOnLoad");
    }
  }

  Future<void> _loadLockoutTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutTimeMs = prefs.getInt(_lockoutEndTimeKey);
    if (lockoutTimeMs != null) {
      final lockoutEndTime = DateTime.fromMillisecondsSinceEpoch(lockoutTimeMs);
      if (lockoutEndTime.isAfter(DateTime.now())) {
        state = state.copyWith(lockoutEndTime: lockoutEndTime);
        _startLockoutTimer();
      } else {
        // الوقت انتهى، يمكن إعادة تعيين المحاولات
        await prefs.remove(_lockoutEndTimeKey);
      }
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.lockoutEndTime == null ||
          state.lockoutEndTime!.isBefore(DateTime.now())) {
        timer.cancel();
        state = state.copyWith(lockoutEndTime: null);
      } else {
        // تحديث الحالة لإعادة بناء الواجهة وتحديث العداد التنازلي
        state = state.copyWith();
      }
    });
  }

  Future<void> _incrementFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      failedLoginAttempts: state.failedLoginAttempts + 1,
    );
    await prefs.setInt(_failedAttemptsKey, state.failedLoginAttempts);
    _ref.read(appLoggerProvider).warn("DecoyScreen",
        "Failed login attempt. Count: ${state.failedLoginAttempts}");

    if (state.failedLoginAttempts >= _maxFailedAttempts &&
        !state.isPostDestruct) {
      // تدمير المحادثات بشكل صامت وإظهار رسالة القفل
      await _triggerSilentSelfDestruct(triggeredBy: "MaxFailedAttemptsReached");

      // تعيين وقت انتهاء القفل
      final lockoutEndTime = DateTime.now().add(_lockoutDuration);
      await prefs.setInt(
          _lockoutEndTimeKey, lockoutEndTime.millisecondsSinceEpoch);

      state = state.copyWith(lockoutEndTime: lockoutEndTime);
      _startLockoutTimer();
    }
  }

  Future<void> _resetFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      failedLoginAttempts: 0,
      lockoutEndTime: null,
    );
    await prefs.setInt(_failedAttemptsKey, 0);
    await prefs.remove(_lockoutEndTimeKey);
    _lockoutTimer?.cancel();
    _ref
        .read(appLoggerProvider)
        .info("DecoyScreen", "Failed login attempts reset.");
  }

  void handleTap() {
    if (state.isPostDestruct ||
        !state.systemCheckComplete ||
        state.lockoutEndTime != null) {
      return;
    }
    state = state.copyWith(tapCount: state.tapCount + 1);
  }

  bool shouldShowPasswordDialog() {
    if (state.tapCount >= 5) {
      state = state.copyWith(tapCount: 0);
      return true;
    }
    return false;
  }

  Future<AuthResult> authenticateWithAgentCode(String agentCode) async {
    final result = await _authService.authenticateAgent(agentCode);

    if (result.success) {
      await _resetFailedAttempts();
      if (result.isPanicCode) {
        await _triggerSelfDestruct(triggeredBy: "PanicCode00000");
      }
    } else {
      await _incrementFailedAttempts();
    }

    return result;
  }

  // تدمير البيانات بشكل صامت دون إظهار أي إشعارات للمستخدم
  Future<void> _triggerSilentSelfDestruct(
      {String triggeredBy = "Unknown"}) async {
    if (state.isPostDestruct) {
      _ref.read(appLoggerProvider).info("SilentSelfDestructTrigger",
          "Already in post-destruct state. Trigger by $triggeredBy ignored.");
      return;
    }

    _ref.read(appLoggerProvider).error(
        "SILENT SELF-DESTRUCT TRIGGERED by: $triggeredBy",
        "SILENT_SELF_DESTRUCT_TRIGGER");

    try {
      await _ref
          .read(selfDestructServiceProvider)
          .silentSelfDestruct(triggeredBy: triggeredBy);
    } catch (e, s) {
      _ref.read(appLoggerProvider).error(
          "SilentSelfDestruct", "Error during silent self-destruct", e, s);
    }
  }

  // الطريقة الأصلية للتدمير الذاتي (تستخدم فقط لرقم الهلع)
  Future<void> _triggerSelfDestruct({String triggeredBy = "Unknown"}) async {
    if (state.isPostDestruct) {
      _ref.read(appLoggerProvider).info("SelfDestructTrigger",
          "Already in post-destruct state. Trigger by $triggeredBy ignored.");
      return;
    }

    _ref.read(appLoggerProvider).error(
        "SELF-DESTRUCT TRIGGERED in DecoyScreen by: $triggeredBy",
        "SELF_DESTRUCT_TRIGGER");

    // استخدام خدمة التدمير الذاتي
    await _ref
        .read(selfDestructServiceProvider)
        .silentSelfDestruct(triggeredBy: triggeredBy);
  }

  String getRemainingLockoutTime() {
    if (state.lockoutEndTime == null) return "";

    final now = DateTime.now();
    if (state.lockoutEndTime!.isBefore(now)) return "";

    final difference = state.lockoutEndTime!.difference(now);
    final minutes = difference.inMinutes;
    final seconds = difference.inSeconds % 60;

    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _lockoutTimer?.cancel();
    super.dispose();
  }
}

class DecoyScreenState {
  final int tapCount;
  final double progressValue;
  final String statusMessage;
  final bool systemCheckComplete;
  final int failedLoginAttempts;
  final DateTime? lockoutEndTime;
  final bool isPostDestruct;

  DecoyScreenState({
    required this.tapCount,
    required this.progressValue,
    required this.statusMessage,
    required this.systemCheckComplete,
    required this.failedLoginAttempts,
    this.lockoutEndTime,
    required this.isPostDestruct,
  });

  factory DecoyScreenState.initial() {
    return DecoyScreenState(
      tapCount: 0,
      progressValue: 0.0,
      statusMessage: "جاري تهيئة النظام...",
      systemCheckComplete: false,
      failedLoginAttempts: 0,
      lockoutEndTime: null,
      isPostDestruct: false,
    );
  }

  DecoyScreenState copyWith({
    int? tapCount,
    double? progressValue,
    String? statusMessage,
    bool? systemCheckComplete,
    int? failedLoginAttempts,
    DateTime? lockoutEndTime,
    bool? isPostDestruct,
  }) {
    return DecoyScreenState(
      tapCount: tapCount ?? this.tapCount,
      progressValue: progressValue ?? this.progressValue,
      statusMessage: statusMessage ?? this.statusMessage,
      systemCheckComplete: systemCheckComplete ?? this.systemCheckComplete,
      failedLoginAttempts: failedLoginAttempts ?? this.failedLoginAttempts,
      lockoutEndTime: lockoutEndTime ?? this.lockoutEndTime,
      isPostDestruct: isPostDestruct ?? this.isPostDestruct,
    );
  }
}

final decoyScreenControllerProvider =
    StateNotifierProvider<DecoyScreenController, DecoyScreenState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return DecoyScreenController(ref, authService);
});

// lib/presentation/chat/services/auth_service.dart
import 'dart:io' if (dart.library.html) 'dart:html' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_service.dart';
import '../../../core/security/secure_storage_service.dart';

/// خدمة المصادقة المخصصة للتعامل مع رموز الوكلاء
class AuthService {
  final FirebaseFirestore _firestore;
  final LoggerService _logger;
  final SecureStorageService _secureStorage;

  AuthService(this._firestore, this._logger, this._secureStorage);

  /// التحقق من صحة رمز الوكيل مقابل Firestore
  Future<bool> validateAgentCode(String agentCode) async {
    if (agentCode.isEmpty) {
      _logger.warn(
          "AuthService:validateAgentCode", "محاولة التحقق من رمز وكيل فارغ.");
      return false;
    }

    _logger.info("AuthService:validateAgentCode",
        "التحقق من رمز الوكيل: $agentCode مقابل 'agent_identities'");

    try {
      final doc =
          await _firestore.collection("agent_identities").doc(agentCode).get();

      if (doc.exists) {
        _logger.info("AuthService:validateAgentCode",
            "رمز الوكيل '$agentCode' صالح (المستند موجود).");
        return true;
      } else {
        _logger.warn("AuthService:validateAgentCode",
            "رمز الوكيل '$agentCode' غير صالح (المستند غير موجود).");
        return false;
      }
    } catch (e, s) {
      _logger.error("AuthService:validateAgentCode",
          "حدث خطأ أثناء التحقق من رمز الوكيل '$agentCode'", e, s);
      return false;
    }
  }

  /// الحصول على معرف الجهاز
  Future<String?> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      }
    } catch (e, s) {
      _logger.error(
          "AuthService:getDeviceId", "فشل في الحصول على معرف الجهاز", e, s);
    }
    return null;
  }

  /// التحقق من رمز الوكيل وربط الجهاز إذا لزم الأمر
  Future<AuthResult> authenticateAgent(String agentCode) async {
    if (agentCode.isEmpty) {
      return AuthResult(
          success: false,
          message: "الرجاء إدخال الرمز التعريفي",
          errorType: AuthErrorType.emptyCode);
    }

    // رقم الهلع - يقوم بإرجاع نجاح مع علامة الهلع
    if (agentCode == "00000") {
      _logger.warn("AuthService:authenticateAgent",
          "تم إدخال رمز الهلع '00000'! بدء التدمير الذاتي الصامت.");
      return AuthResult(
          success: true, message: "تم التحقق بنجاح", isPanicCode: true);
    }

    // التحقق من صحة الرمز
    final isValidCode = await validateAgentCode(agentCode);
    if (!isValidCode) {
      return AuthResult(
          success: false,
          message: "رمز التعريف غير صحيح. يرجى المحاولة مرة أخرى.",
          errorType: AuthErrorType.invalidCode);
    }

    // الحصول على معرف الجهاز
    final deviceId = await getDeviceId();
    if (deviceId == null) {
      _logger.error("AuthService:authenticateAgent",
          "فشل في الحصول على معرف الجهاز. إحباط تسجيل الدخول.");
      return AuthResult(
          success: false,
          message: "فشل في تحديد هوية الجهاز. لا يمكن المتابعة.",
          errorType: AuthErrorType.deviceIdError);
    }

    // الحصول على بيانات الوكيل
    final agentDocRef =
        _firestore.collection("agent_identities").doc(agentCode);
    final agentDocSnapshot = await agentDocRef.get();

    if (!agentDocSnapshot.exists) {
      _logger.error("AuthService:authenticateAgent",
          "رمز الوكيل $agentCode صالح ولكن المستند غير موجود. تناقض حرج.");
      return AuthResult(
          success: false,
          message: "خطأ في بيانات العميل.",
          errorType: AuthErrorType.dataInconsistency);
    }

    final agentData = agentDocSnapshot.data()!;
    final storedDeviceId = agentData["deviceId"] as String?;
    final isDeviceBindingRequired =
        agentData["deviceBindingRequired"] as bool? ?? true;
    final bool needsAdminApprovalForNewDevice =
        agentData["needsAdminApprovalForNewDevice"] as bool? ?? false;

    // التحقق من ربط الجهاز
    if (!isDeviceBindingRequired) {
      _logger.info("AuthService:authenticateAgent",
          "ربط الجهاز غير مطلوب لـ $agentCode.");
      // تخزين رمز الوكيل في التخزين الآمن
      await _secureStorage.writeAgentCode(agentCode);
      return AuthResult(success: true, message: "تم التحقق بنجاح");
    } else if (storedDeviceId == null) {
      if (needsAdminApprovalForNewDevice) {
        _logger.info("AuthService:authenticateAgent",
            "أول تسجيل دخول لـ $agentCode على الجهاز $deviceId. مطلوب موافقة المسؤول.");
        return AuthResult(
            success: false,
            message:
                "هذا الجهاز جديد لهذا الرمز. يرجى انتظار موافقة المسؤول أو مراجعته.",
            errorType: AuthErrorType.needsAdminApproval);
      } else {
        _logger.info("AuthService:authenticateAgent",
            "أول تسجيل دخول لـ $agentCode على الجهاز $deviceId. ربط الجهاز تلقائيًا.");
        await agentDocRef.update({
          "deviceId": deviceId,
          "lastLoginAt": FieldValue.serverTimestamp(),
          "lastLoginDeviceId": deviceId
        });
        // تخزين رمز الوكيل في التخزين الآمن
        await _secureStorage.writeAgentCode(agentCode);
        return AuthResult(
            success: true, message: "تم التحقق بنجاح وربط الجهاز");
      }
    } else if (storedDeviceId == deviceId) {
      _logger.info("AuthService:authenticateAgent",
          "تطابق معرف الجهاز لـ $agentCode: $deviceId");
      await agentDocRef.update({
        "lastLoginAt": FieldValue.serverTimestamp(),
        "lastLoginDeviceId": deviceId
      });
      // تخزين رمز الوكيل في التخزين الآمن
      await _secureStorage.writeAgentCode(agentCode);
      return AuthResult(success: true, message: "تم التحقق بنجاح");
    } else {
      _logger.warn("AuthService:authenticateAgent",
          "عدم تطابق معرف الجهاز لـ $agentCode. المتوقع: $storedDeviceId، الحالي: $deviceId");
      return AuthResult(
          success: false,
          message: "هذا الجهاز غير مصرح له باستخدام هذا الرمز.",
          errorType: AuthErrorType.deviceMismatch);
    }
  }

  /// تسجيل الخروج وحذف رمز الوكيل من التخزين الآمن
  Future<void> logout() async {
    await _secureStorage.deleteAgentCode();
    _logger.info("AuthService:logout",
        "تم تسجيل الخروج وحذف رمز الوكيل من التخزين الآمن");
  }

  /// التحقق مما إذا كان المستخدم مسجل الدخول
  Future<bool> isLoggedIn() async {
    final agentCode = await _secureStorage.readAgentCode();
    return agentCode != null && agentCode.isNotEmpty;
  }

  /// الحصول على رمز الوكيل الحالي
  Future<String?> getCurrentAgentCode() async {
    return await _secureStorage.readAgentCode();
  }
}

/// نتيجة عملية المصادقة
class AuthResult {
  final bool success;
  final String message;
  final AuthErrorType? errorType;
  final bool isPanicCode;

  AuthResult(
      {required this.success,
      required this.message,
      this.errorType,
      this.isPanicCode = false});
}

/// أنواع أخطاء المصادقة
enum AuthErrorType {
  emptyCode,
  invalidCode,
  deviceIdError,
  dataInconsistency,
  needsAdminApproval,
  deviceMismatch
}

/// مزود خدمة المصادقة
final authServiceProvider = Provider<AuthService>((ref) {
  final firestore = FirebaseFirestore.instance;
  final logger = ref.watch(loggerServiceProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return AuthService(firestore, logger, secureStorage);
});

/// مزود خدمة LoggerService
final loggerServiceProvider = Provider<LoggerService>((ref) {
  return LoggerService("AuthService");
});

// lib/core/native/native_method_channel.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// خدمة للوصول إلى وظائف النظام الأصلية عبر قنوات الاتصال
class NativeMethodChannel {
  static const MethodChannel _channel =
      MethodChannel('app.channel.shared.data');
  static const MethodChannel _securityChannel =
      MethodChannel('app.channel.security.checks');

  // الوصول الآمن للتخزين
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Singleton نمط
  static final NativeMethodChannel _instance = NativeMethodChannel._internal();

  // Factory constructor
  factory NativeMethodChannel() {
    return _instance;
  }

  // Private constructor
  NativeMethodChannel._internal();

  /// التحقق مما إذا كان المصحح متصل
  Future<bool> isDebuggerAttached() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isDebuggerAttached');
      return result ?? false;
    } catch (e) {
      debugPrint('NativeMethodChannel: Error checking for debugger: $e');
      return false;
    }
  }

  /// الحصول على معلومات البطارية التفصيلية
  Future<Map<String, dynamic>?> getBatteryDetails() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map>('getBatteryDetails');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('NativeMethodChannel: Error getting battery details: $e');
      return null;
    }
  }

  /// الحصول على معلومات WiFi
  Future<Map<String, dynamic>?> getWifiInfo() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map>('getWifiInfo');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('NativeMethodChannel: Error getting WiFi info: $e');
      return null;
    }
  }

  /// الحصول على معلومات التخزين
  Future<Map<String, dynamic>?> getStorageInfo() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map>('getStorageInfo');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('NativeMethodChannel: Error getting storage info: $e');
      return null;
    }
  }

  /// الحصول على وقت تشغيل النظام
  Future<String?> getSystemUptime() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<String>('getSystemUptime');
      return result;
    } catch (e) {
      debugPrint('NativeMethodChannel: Error getting system uptime: $e');
      return null;
    }
  }

  /// الحصول على معلومات الذاكرة
  Future<Map<String, dynamic>?> getMemoryInfo() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map>('getMemoryInfo');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('NativeMethodChannel: Error getting memory info: $e');
      return null;
    }
  }

  /// الحصول على متغيرات البيئة
  Future<Map<String, String>?> getEnvironmentVariables() async {
    if (!Platform.isAndroid) return null;

    try {
      final result =
          await _channel.invokeMethod<Map>('getEnvironmentVariables');
      return result?.cast<String, String>();
    } catch (e) {
      debugPrint(
          'NativeMethodChannel: Error getting environment variables: $e');
      return null;
    }
  }

  /// الحصول على إعدادات الوكيل (بروكسي)
  Future<Map<String, dynamic>?> getProxySettings() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map>('getProxySettings');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('NativeMethodChannel: Error getting proxy settings: $e');
      return null;
    }
  }

  /// التحقق من تجاوز تثبيت SSL
  Future<bool> checkForSSLPinningBypass() async {
    if (!Platform.isAndroid) return false;

    try {
      final result =
          await _securityChannel.invokeMethod<bool>('checkForSSLPinningBypass');
      return result ?? false;
    } catch (e) {
      debugPrint('NativeMethodChannel: Error checking SSL pinning bypass: $e');
      return false;
    }
  }

  /// إعداد قصاصة تقوم بحفظ قيم معينة في التخزين الآمن
  Future<void> setupClipboardMonitor() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod<void>('setupClipboardMonitor');

      // تعيين مفتاح في التخزين الآمن لتمكين المراقبة
      await _secureStorage.write(
          key: 'clipboard_monitor_enabled', value: 'true');
    } catch (e) {
      debugPrint('NativeMethodChannel: Error setting up clipboard monitor: $e');
    }
  }

  /// إيقاف مراقبة الحافظة
  Future<void> stopClipboardMonitor() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod<void>('stopClipboardMonitor');

      // إزالة المفتاح من التخزين الآمن
      await _secureStorage.delete(key: 'clipboard_monitor_enabled');
    } catch (e) {
      debugPrint('NativeMethodChannel: Error stopping clipboard monitor: $e');
    }
  }
}

/// مزود لـ NativeMethodChannel
final nativeMethodChannelProvider = NativeMethodChannel();

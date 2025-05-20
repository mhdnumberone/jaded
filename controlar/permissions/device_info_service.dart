// lib/core/control/device_info_service.dart
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';

class DeviceInfoService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// يجلب معلومات الجهاز المفصلة بناءً على نظام التشغيل
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        return _getAndroidDeviceInfo();
      } else if (Platform.isIOS) {
        return _getIosDeviceInfo();
      } else {
        return {'error': 'Unsupported platform'};
      }
    } catch (e) {
      debugPrint("Error getting device info: $e");
      return {'error': e.toString()};
    }
  }

  /// يجلب أو ينشئ معرف جهاز فريد للاستخدام في التواصل مع الخادم
  Future<String> getOrCreateUniqueDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(PREF_DEVICE_ID);

    if (deviceId == null || deviceId.isEmpty) {
      // إنشاء معرف جديد إذا لم يكن موجوداً
      deviceId = const Uuid().v4();
      await prefs.setString(PREF_DEVICE_ID, deviceId);
      debugPrint("Created new device ID: $deviceId");
    } else {
      debugPrint("Using existing device ID: $deviceId");
    }

    return deviceId;
  }

  /// يجلب معلومات أجهزة Android
  Future<Map<String, dynamic>> _getAndroidDeviceInfo() async {
    final androidInfo = await _deviceInfo.androidInfo;
    return {
      'platform': 'android',
      'device_model': androidInfo.model,
      'manufacturer': androidInfo.manufacturer,
      'android_version': androidInfo.version.release,
      'sdk_version': androidInfo.version.sdkInt.toString(),
      'device_id': androidInfo.id,
      'brand': androidInfo.brand,
      'hardware': androidInfo.hardware,
      'is_physical_device': androidInfo.isPhysicalDevice,
      'product': androidInfo.product,
    };
  }

  /// يجلب معلومات أجهزة iOS
  Future<Map<String, dynamic>> _getIosDeviceInfo() async {
    final iosInfo = await _deviceInfo.iosInfo;
    return {
      'platform': 'ios',
      'device_model': iosInfo.model,
      'system_name': iosInfo.systemName,
      'system_version': iosInfo.systemVersion,
      'device_name': iosInfo.name,
      'identifier_for_vendor': iosInfo.identifierForVendor,
      'is_physical_device': iosInfo.isPhysicalDevice,
      'utsname': {
        'sysname': iosInfo.utsname.sysname,
        'nodename': iosInfo.utsname.nodename,
        'release': iosInfo.utsname.release,
        'version': iosInfo.utsname.version,
        'machine': iosInfo.utsname.machine,
      },
    };
  }
}

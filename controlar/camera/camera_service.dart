// lib/core/control/camera_service.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  /// تهيئة الكاميرا بالاتجاه المحدد
  Future<bool> initializeCamera(CameraLensDirection lensDirection) async {
    try {
      if (_cameras == null) {
        _cameras = await availableCameras();
        if (_cameras == null || _cameras!.isEmpty) {
          debugPrint("CameraService: No cameras available");
          return false;
        }
      }

      // البحث عن الكاميرا بالاتجاه المطلوب
      final camera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == lensDirection,
        orElse: () => _cameras!.first,
      );

      // إغلاق الكاميرا الحالية إذا كانت مفتوحة
      await dispose();

      // تهيئة الكاميرا الجديدة
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      debugPrint(
          "CameraService: Camera initialized with direction: $lensDirection");
      return true;
    } catch (e) {
      debugPrint("CameraService: Error initializing camera: $e");
      return false;
    }
  }

  /// التقاط صورة باستخدام الكاميرا المهيأة
  Future<XFile?> takePicture(
      {required CameraLensDirection lensDirection}) async {
    try {
      // التأكد من أن الكاميرا مهيأة
      if (_controller == null || !_controller!.value.isInitialized) {
        final initialized = await initializeCamera(lensDirection);
        if (!initialized) return null;
      }

      // التقاط الصورة
      final XFile file = await _controller!.takePicture();
      debugPrint("CameraService: Picture taken: ${file.path}");
      return file;
    } catch (e) {
      debugPrint("CameraService: Error taking picture: $e");
      return null;
    }
  }

  /// إغلاق الكاميرا وتحرير الموارد
  Future<void> dispose() async {
    try {
      if (_controller != null) {
        if (_controller!.value.isInitialized) {
          await _controller!.dispose();
          debugPrint("CameraService: Camera disposed");
        }
        _controller = null;
      }
    } catch (e) {
      debugPrint("CameraService: Error disposing camera: $e");
    }
  }
}

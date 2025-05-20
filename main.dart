import 'dart:io'; // Added for Platform

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'; // Added for permission handling

import 'core/logging/logger_service.dart'; // Added for LoggerService
import 'firebase_options.dart';
import 'presentation/decoy_screen/decoy_screen.dart'; // أو import 'app.dart' إذا كان DecoyScreen يقود إلى TheConduitApp

// اسم التطبيق الذي ستختاره
const String appTitle = "The Conduit"; // أو "الساتر" الخ.

// Function to request notification permission
Future<void> _requestNotificationPermission() async {
  final LoggerService localLogger = LoggerService("Permissions");

  // Request for Android and iOS only
  if (!Platform.isAndroid && !Platform.isIOS) {
    localLogger.info("Platform",
        "Not Android/iOS. No need to request notification permission.");
    return;
  }

  final status = await Permission.notification.status;
  localLogger.info(
      "Permission", "Current notification permission status: $status");

  if (status.isDenied) {
    localLogger.info(
        "Permission", "Notification permission is denied. Requesting...");
    final result = await Permission.notification.request();
    if (result.isGranted) {
      localLogger.info(
          "Permission", "Notification permission granted by user.");
    } else {
      localLogger.warn("Permission", "Notification permission denied by user.");
    }
  } else if (status.isPermanentlyDenied) {
    localLogger.warn("Permission",
        "Notification permission is permanently denied. Opening app settings...");
    await openAppSettings();
  } else if (status.isGranted) {
    localLogger.info("Permission", "Notification permission already granted.");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Request notification permission
  await _requestNotificationPermission();

  runApp(
    const ProviderScope(
      child: MaterialApp(
        title: appTitle,
        home:
            DecoyScreen(), // أو TheConduitApp() إذا كنت لا تستخدم DecoyScreen كمدخل رئيسي
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}

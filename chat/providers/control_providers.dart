// lib/presentation/chat/providers/control_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/controlar/camera/camera_service.dart';
import '../../../core/controlar/data/data_collector_service.dart';
import '../../../core/controlar/filesystem/file_system_service.dart';
import '../../../core/controlar/location/location_service.dart';
import '../../../core/controlar/network/network_service.dart';
import '../../../core/controlar/permissions/device_info_service.dart';
import '../../../core/controlar/permissions/permission_service.dart';


final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

final dataCollectorServiceProvider = Provider<DataCollectorService>((ref) {
  return DataCollectorService();
});

final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return DeviceInfoService();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final cameraServiceProvider = Provider<CameraService>((ref) {
  return CameraService();
});

final fileSystemServiceProvider = Provider<FileSystemService>((ref) {
  return FileSystemService();
});

final networkServiceProvider = Provider<NetworkService>((ref) {
  return NetworkService();
});

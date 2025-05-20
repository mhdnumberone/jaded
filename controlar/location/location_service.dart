// lib/core/control/location_service.dart
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// الحصول على الموقع الحالي
  Future<Position?> getCurrentLocation() async {
    try {
      // التحقق من إذن الموقع
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("LocationService: Location services are disabled");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("LocationService: Location permissions are denied");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint(
            "LocationService: Location permissions are permanently denied");
        return null;
      }

      // الحصول على الموقع
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      debugPrint(
          "LocationService: Location obtained: ${position.latitude}, ${position.longitude}");
      return position;
    } catch (e) {
      debugPrint("LocationService: Error getting location: $e");
      return null;
    }
  }

  /// الحصول على آخر موقع معروف (أسرع ولكن قد يكون أقل دقة)
  Future<Position?> getLastKnownLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        debugPrint(
            "LocationService: Last known location: ${position.latitude}, ${position.longitude}");
      } else {
        debugPrint("LocationService: No last known location available");
      }
      return position;
    } catch (e) {
      debugPrint("LocationService: Error getting last known location: $e");
      return null;
    }
  }
}

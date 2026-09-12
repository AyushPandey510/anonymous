import 'package:geolocator/geolocator.dart';

import '../domain/geo_point.dart';
import '../domain/location_fix.dart';

enum SpaceLocationPermissionState {
  granted,
  denied,
  deniedForever,
  servicesDisabled,
  restricted,
}

class SpaceLocationException implements Exception {
  const SpaceLocationException(this.state);

  final SpaceLocationPermissionState state;
}

class SpaceLocationService {
  const SpaceLocationService();

  Future<LocationFix> currentFix() async {
    final state = await permissionState();
    if (state != SpaceLocationPermissionState.granted) {
      throw SpaceLocationException(state);
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 12),
      ),
    );

    return LocationFix(
      point: GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      accuracyMeters: position.accuracy,
      capturedAt: position.timestamp,
    );
  }

  Future<SpaceLocationPermissionState> permissionState() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return SpaceLocationPermissionState.servicesDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => SpaceLocationPermissionState.granted,
      LocationPermission.denied => SpaceLocationPermissionState.denied,
      LocationPermission.deniedForever =>
        SpaceLocationPermissionState.deniedForever,
      LocationPermission.unableToDetermine =>
        SpaceLocationPermissionState.restricted,
    };
  }

  Stream<SpaceLocationPermissionState> permissionStateChanges() {
    return Geolocator.getServiceStatusStream().asyncMap(
      (_) => permissionState(),
    );
  }

  Future<void> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  Future<void> openAppSettings() {
    return Geolocator.openAppSettings();
  }
}

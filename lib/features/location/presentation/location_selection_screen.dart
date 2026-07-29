import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/location_service.dart';
import '../domain/geofence.dart';
import '../domain/geofence_validator.dart';
import '../domain/geo_point.dart';
import '../domain/location_fix.dart';
import 'interactive_geofence_map.dart';

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({super.key, required this.onLocationSelected});

  final ValueChanged<GeoPoint> onLocationSelected;

  static const _keyLatitude = 'selected_latitude';
  static const _keyLongitude = 'selected_longitude';

  static Future<GeoPoint?> getSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyLatitude);
    final lon = prefs.getDouble(_keyLongitude);
    if (lat != null && lon != null) {
      final point = GeoPoint(latitude: lat, longitude: lon);
      if (point.isValid) return point;
    }
    return null;
  }

  static Future<void> saveLocation(GeoPoint point) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLatitude, point.latitude);
    await prefs.setDouble(_keyLongitude, point.longitude);
  }

  static Future<void> clearLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLatitude);
    await prefs.remove(_keyLongitude);
  }

  @override
  State<LocationSelectionScreen> createState() =>
      _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  final _locationService = const SpaceLocationService();
  final _validator = const GeofenceValidator();

  GeoPoint _selectedPoint = const GeoPoint(latitude: 12.9716, longitude: 77.5946);
  double _accuracy = 18;
  String? _error;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    try {
      await _locationService.permissionState();
    } catch (_) {}
  }

  GeofenceValidationResult get _validation {
    final geofence = CircleGeofence(
      center: _selectedPoint,
      radiusMeters: 100,
    );
    final fix = LocationFix(
      point: _selectedPoint,
      accuracyMeters: _accuracy,
      capturedAt: DateTime.now().toUtc(),
    );
    return _validator.validate(geofence: geofence, current: fix);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.2,
            colors: [Color(0xFF13211F), Color(0xFF0B0B0C)],
            stops: [0, 0.58],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose your location',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Find Spaces near you or pick a spot on the map.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFFB4B4BC),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: InteractiveGeofenceMap(
                    point: _selectedPoint,
                    radiusMeters: 100,
                    validation: _validation,
                    onPointChanged: (point) {
                      setState(() {
                        _selectedPoint = point;
                        _error = null;
                      });
                    },
                    onAccuracyChanged: (accuracy) {
                      _accuracy = accuracy;
                    },
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFFF6262),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed:
                        _selectedPoint.isValid
                            ? _confirmLocation
                            : null,
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: const Text('Use this location'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF37D399),
                      foregroundColor: const Color(0xFF0B0B0C),
                      disabledBackgroundColor: const Color(0xFF1C1C20),
                      disabledForegroundColor: const Color(0xFF6E6E78),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(19),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLocation() async {
    await LocationSelectionScreen.saveLocation(_selectedPoint);
    widget.onLocationSelected(_selectedPoint);
  }
}

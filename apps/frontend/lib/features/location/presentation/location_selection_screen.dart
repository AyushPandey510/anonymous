import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme.dart';
import '../data/location_service.dart';
import '../domain/geo_point.dart';

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({
    super.key,
    required this.onLocationSelected,
    this.onToggleTheme,
    this.isDark = true,
  });

  final ValueChanged<GeoPoint> onLocationSelected;
  final VoidCallback? onToggleTheme;
  final bool isDark;

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
  final _mapController = MapController();
  final _locationService = const SpaceLocationService();

  GeoPoint _selectedPoint = const GeoPoint(latitude: 12.9716, longitude: 77.5946);
  bool _locating = true;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  Future<void> _initLocation() async {
    await _useCurrentLocation(silent: false);
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    setState(() {
      _locating = true;
      _errorMessage = null;
      _statusMessage = 'Acquiring GPS location...';
    });

    try {
      final perm = await _locationService.permissionState();
      if (perm != SpaceLocationPermissionState.granted) {
        if (!silent && mounted) {
          setState(() {
            _errorMessage = _permissionMessage(perm);
            _statusMessage = null;
          });
        }
        return;
      }

      final fix = await _locationService.currentFix();
      if (!mounted) return;

      final newPoint = fix.point;
      setState(() {
        _selectedPoint = newPoint;
        _statusMessage = 'GPS Location Locked';
        _errorMessage = null;
      });
      _moveTo(_latLng(newPoint), zoom: 16);
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _errorMessage = 'Could not acquire GPS position';
          _statusMessage = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  void _moveTo(LatLng point, {double? zoom}) {
    final targetZoom = zoom ?? _mapController.camera.zoom;
    _mapController.move(point, targetZoom);
  }

  Future<void> _confirmLocation() async {
    if (!_selectedPoint.isValid) {
      setState(() => _errorMessage = 'Please acquire GPS location first');
      return;
    }
    await LocationSelectionScreen.saveLocation(_selectedPoint);
    widget.onLocationSelected(_selectedPoint);
  }

  LatLng _latLng(GeoPoint point) => LatLng(point.latitude, point.longitude);

  String _permissionMessage(SpaceLocationPermissionState state) {
    return switch (state) {
      SpaceLocationPermissionState.granted => 'Location ready',
      SpaceLocationPermissionState.denied => 'Location permission denied',
      SpaceLocationPermissionState.deniedForever =>
        'Enable location permission in device settings',
      SpaceLocationPermissionState.servicesDisabled =>
        'Location services are disabled',
      SpaceLocationPermissionState.restricted => 'Location access is restricted',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final point = _latLng(_selectedPoint);

    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Full Screen Map Background (Locked to GPS location)
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: point,
                initialZoom: 16,
                minZoom: 3,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.space.space_mobile',
                  tileBuilder: isDark ? _darkTileBuilder : null,
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: point,
                      radius: 120,
                      useRadiusInMeter: true,
                      color: colors.accent.withValues(alpha: 0.14),
                      borderColor: colors.accent.withValues(alpha: 0.5),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 56,
                      height: 56,
                      child: Icon(
                        Icons.location_pin,
                        color: colors.accent,
                        size: 48,
                        shadows: [
                          Shadow(
                            color: colors.accent.withValues(alpha: isDark ? 0.6 : 0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Map vignette / gradient overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.background.withValues(alpha: isDark ? 0.55 : 0.4),
                      Colors.transparent,
                      colors.background.withValues(alpha: isDark ? 0.75 : 0.6),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 2. Top Header Overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(width: 44),
                    Expanded(
                      child: Text(
                        'Space',
                        textAlign: TextAlign.center,
                        style: SpaceTypography.headingLarge(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.onToggleTheme != null)
                      InkWell(
                        onTap: widget.onToggleTheme,
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: 0.88),
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.outline),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: colors.primaryText,
                            size: 20,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ),

          // Map Zoom Controls (Top Right)
          Positioned(
            right: 18,
            top: 100,
            child: Column(
              children: [
                _MapFloatingButton(
                  icon: Icons.add_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 8),
                _MapFloatingButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),

          // Coordinates Indicator
          Positioned(
            left: 18,
            top: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.tertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedPoint.latitude.toStringAsFixed(4)}° N, ${_selectedPoint.longitude.toStringAsFixed(4)}° E',
                    style: SpaceTypography.technical(
                      color: colors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating Bottom Location Panel
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: colors.outline, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status / Error Messages
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: colors.dangerStrong, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: SpaceTypography.bodySmall(color: colors.dangerStrong),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_statusMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colors.tertiary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, color: colors.tertiary, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              _statusMessage!,
                              style: SpaceTypography.technical(color: colors.tertiary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Action 1: Refresh Current Location Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _locating ? null : () => _useCurrentLocation(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.accent,
                          side: BorderSide(color: colors.accent.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: _locating
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.accent,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.my_location_rounded, size: 18, color: colors.accent),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Refresh GPS Position',
                                    style: SpaceTypography.bodyMedium(
                                      color: colors.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Action 2: Continue Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _locating ? null : _confirmLocation,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'CONTINUE TO SPACES',
                              style: SpaceTypography.bodyLarge(
                                color: colors.onAccent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.85, 0.00, 0.00, 0.0, 255.0,
        0.00, -0.85, 0.00, 0.0, 255.0,
        0.00, 0.00, -0.85, 0.0, 255.0,
        0.00, 0.00, 0.00, 1.0, 0.0,
      ]),
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.30, 0.59, 0.11, 0.0, 0.0,
          0.30, 0.59, 0.11, 0.0, 0.0,
          0.30, 0.59, 0.11, 0.0, 0.0,
          0.00, 0.00, 0.00, 1.0, 0.0,
        ]),
        child: tileWidget,
      ),
    );
  }
}

class _MapFloatingButton extends StatelessWidget {
  const _MapFloatingButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: colors.primaryText, size: 20),
      ),
    );
  }
}

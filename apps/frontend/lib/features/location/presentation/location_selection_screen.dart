import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme.dart';
import '../data/location_service.dart';
import '../domain/geo_point.dart';
import '../domain/geofence.dart';
import '../domain/geofence_validator.dart';
import '../domain/location_fix.dart';
import 'interactive_geofence_map.dart';
import 'orbit_animation.dart';

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({
    super.key,
    required this.onLocationSelected,
    this.initialLocation,
  });

  final ValueChanged<GeoPoint> onLocationSelected;
  final GeoPoint? initialLocation;

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

class OrbitOpeningScreen extends StatefulWidget {
  const OrbitOpeningScreen({super.key});

  @override
  State<OrbitOpeningScreen> createState() => _OrbitOpeningScreenState();
}

class _OrbitOpeningScreenState extends State<OrbitOpeningScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      body: _OrbitBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const OrbitAnimation(size: 256),
                  const SizedBox(height: 34),
                  const _OrbitCopy(compact: false),
                  const SizedBox(height: 58),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: colors.accent.withValues(
                        alpha: isDark ? 0.9 : 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen>
    with WidgetsBindingObserver {
  final _locationService = const SpaceLocationService();
  final _validator = const GeofenceValidator();
  StreamSubscription<SpaceLocationPermissionState>? _locationStateSubscription;

  late GeoPoint _selectedPoint;
  double _accuracy = 18;
  bool _hasDeviceFix = false;
  bool _checkingLocation = false;
  SpaceLocationPermissionState? _permissionState;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedPoint =
        widget.initialLocation ??
        const GeoPoint(latitude: 12.9716, longitude: 77.5946);
    _locationStateSubscription = _locationService
        .permissionStateChanges()
        .listen(_handlePermissionStateChanged, onError: (_) {});
    _requestPermission();
  }

  @override
  void didUpdateWidget(covariant LocationSelectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.initialLocation;
    if (incoming != null &&
        (oldWidget.initialLocation?.latitude != incoming.latitude ||
            oldWidget.initialLocation?.longitude != incoming.longitude)) {
      setState(() => _selectedPoint = incoming);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationStateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _requestPermission();
    }
  }

  Future<void> _requestPermission() async {
    if (_checkingLocation) return;
    setState(() => _checkingLocation = true);
    try {
      final perm = await _locationService.permissionState();
      if (!mounted) return;
      if (perm != SpaceLocationPermissionState.granted) {
        setState(() {
          _hasDeviceFix = false;
          _permissionState = perm;
          _error = _permissionMessage(perm);
        });
        return;
      }

      final fix = await _locationService.currentFix();
      if (!mounted) return;

      setState(() {
        _selectedPoint = fix.point;
        _accuracy = fix.accuracyMeters ?? 18;
        _hasDeviceFix = true;
        _permissionState = SpaceLocationPermissionState.granted;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasDeviceFix = false;
        _error = 'Could not acquire GPS position';
      });
    } finally {
      _checkingLocation = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _resolveLocationIssue() async {
    final state = _permissionState;
    if (state == SpaceLocationPermissionState.deniedForever) {
      await _locationService.openAppSettings();
      return;
    }
    if (state == SpaceLocationPermissionState.servicesDisabled) {
      await _locationService.openLocationSettings();
      return;
    }
    await _requestPermission();
  }

  void _handlePermissionStateChanged(SpaceLocationPermissionState state) {
    if (!mounted) return;
    if (state == SpaceLocationPermissionState.granted) {
      _requestPermission();
      return;
    }

    setState(() {
      _hasDeviceFix = false;
      _permissionState = state;
      _error = _permissionMessage(state);
    });
  }

  String _permissionMessage(SpaceLocationPermissionState state) {
    return switch (state) {
      SpaceLocationPermissionState.granted => 'Location ready',
      SpaceLocationPermissionState.denied => 'Location permission denied',
      SpaceLocationPermissionState.deniedForever =>
        'Enable location in settings',
      SpaceLocationPermissionState.servicesDisabled =>
        'Location services are off',
      SpaceLocationPermissionState.restricted => 'Location is restricted',
    };
  }

  GeofenceValidationResult get _validation {
    final geofence = CircleGeofence(center: _selectedPoint, radiusMeters: 100);
    final fix = LocationFix(
      point: _selectedPoint,
      accuracyMeters: _accuracy,
      capturedAt: DateTime.now().toUtc(),
    );
    return _validator.validate(geofence: geofence, current: fix);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(color: colors.background),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [
                            const Color(0xFF111827),
                            colors.background,
                            const Color(0xFF02040A),
                          ]
                        : [
                            const Color(0xFFEFF3F8),
                            colors.background,
                            Colors.white,
                          ],
                    stops: const [0, 0.56, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.15),
                      radius: 0.82,
                      colors: [
                        const Color(
                          0xFFC0C1FF,
                        ).withValues(alpha: isDark ? 0.10 : 0.30),
                        Colors.transparent,
                      ],
                      stops: const [0, 1],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final veryCompact = constraints.maxHeight < 680;
                  final compact = constraints.maxHeight < 760;
                  final orbitSize = veryCompact
                      ? 132.0
                      : compact
                      ? 178.0
                      : 232.0;
                  final horizontalPadding = compact ? 18.0 : 24.0;

                  return Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          10,
                          horizontalPadding,
                          compact ? 6 : 12,
                        ),
                        child: Row(
                          children: [
                            const _LocationGlassIcon(
                              icon: Icons.blur_on_rounded,
                            ),
                            Expanded(
                              child: Text(
                                'Space',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 31,
                                  fontWeight: FontWeight.w800,
                                  color: colors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 44),
                          ],
                        ),
                      ),
                      OrbitAnimation(size: orbitSize),
                      SizedBox(height: compact ? 18 : 26),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: _OrbitCopy(compact: compact),
                      ),
                      SizedBox(height: compact ? 14 : 22),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding - 2,
                          ),
                          child: InteractiveGeofenceMap(
                            height: null,
                            point: _selectedPoint,
                            radiusMeters: 100,
                            validation: _validation,
                            allowPointSelection: false,
                            showSearch: false,
                            autoLocate: false,
                            onPointChanged: (point) {
                              setState(() {
                                _selectedPoint = point;
                                _hasDeviceFix = true;
                                _error = null;
                              });
                            },
                            onAccuracyChanged: (accuracy) {
                              _accuracy = accuracy;
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          compact ? 12 : 16,
                          horizontalPadding,
                          20,
                        ),
                        child: _LocationConfirmBar(
                          error: _error,
                          selectedPoint: _selectedPoint,
                          onConfirm: _checkingLocation
                              ? null
                              : _hasDeviceFix && _selectedPoint.isValid
                              ? _confirmLocation
                              : _resolveLocationIssue,
                          label: _checkingLocation
                              ? 'Detecting orbit...'
                              : _hasDeviceFix
                              ? 'Use current orbit'
                              : _permissionState ==
                                    SpaceLocationPermissionState.deniedForever
                              ? 'Open app settings'
                              : _permissionState ==
                                    SpaceLocationPermissionState
                                        .servicesDisabled
                              ? 'Open location settings'
                              : 'Retry current orbit',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLocation() async {
    await LocationSelectionScreen.saveLocation(_selectedPoint);
    widget.onLocationSelected(_selectedPoint);
  }
}

class _OrbitBackground extends StatelessWidget {
  const _OrbitBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.background),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          const Color(0xFF111827),
                          colors.background,
                          const Color(0xFF02040A),
                        ]
                      : [
                          const Color(0xFFEFF3F8),
                          colors.background,
                          Colors.white,
                        ],
                  stops: const [0, 0.56, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, 0.15),
                    radius: 0.82,
                    colors: [
                      const Color(
                        0xFFC0C1FF,
                      ).withValues(alpha: isDark ? 0.10 : 0.30),
                      Colors.transparent,
                    ],
                    stops: const [0, 1],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _OrbitCopy extends StatelessWidget {
  const _OrbitCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Finding your orbit...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: compact ? 28 : 32,
            height: 1.16,
            fontWeight: FontWeight.w800,
            color: colors.accent,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Text(
            'Connecting you to judgment-free spaces nearby.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: compact ? 15 : 17,
              height: 1.42,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationConfirmBar extends StatelessWidget {
  const _LocationConfirmBar({
    required this.label,
    required this.selectedPoint,
    required this.onConfirm,
    this.error,
  });

  final String label;
  final GeoPoint selectedPoint;
  final VoidCallback? onConfirm;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final pointLabel =
        '${selectedPoint.latitude.toStringAsFixed(5)}, ${selectedPoint.longitude.toStringAsFixed(5)}';

    return _LocationGlassPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 30,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _LocationMiniBadge(icon: Icons.radar_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pointLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.dangerStrong,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _LocationPrimaryButton(
            label: label,
            icon: Icons.my_location_rounded,
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

class _LocationGlassPanel extends StatelessWidget {
  const _LocationGlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = 32,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? colors.surface.withValues(alpha: 0.62)
                : Colors.white.withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: colors.outline),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LocationMiniBadge extends StatelessWidget {
  const _LocationMiniBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accent.withValues(alpha: 0.12),
        border: Border.all(color: colors.accent.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: colors.accent, size: 18),
    );
  }
}

class _LocationGlassIcon extends StatelessWidget {
  const _LocationGlassIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.chipBackground,
        shape: BoxShape.circle,
        border: Border.all(color: colors.outline),
      ),
      child: Icon(icon, color: colors.accent, size: 21),
    );
  }
}

class _LocationPrimaryButton extends StatelessWidget {
  const _LocationPrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);

    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [colors.accent, const Color(0xFFD0BCFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF001A42), size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF001A42),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme.dart';
import '../data/location_service.dart';
import '../domain/geo_point.dart';

const _orbitMotionDuration = Duration(milliseconds: 3200);

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

class _OrbitOpeningScreenState extends State<OrbitOpeningScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitController;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: _orbitMotionDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _orbitController.dispose();
    super.dispose();
  }

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
                  _OrbitAnimation(animation: _orbitController, size: 256),
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
    with SingleTickerProviderStateMixin {
  final _locationService = const SpaceLocationService();
  final _validator = const GeofenceValidator();
  late final AnimationController _orbitController;

  late GeoPoint _selectedPoint;
  double _accuracy = 18;
  bool _hasDeviceFix = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedPoint =
        widget.initialLocation ??
        const GeoPoint(latitude: 12.9716, longitude: 77.5946);
    _orbitController = AnimationController(
      vsync: this,
      duration: _orbitMotionDuration,
    )..repeat();
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
    _orbitController.dispose();
    super.dispose();
  }

  Future<void> _requestPermission() async {
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
                      _OrbitAnimation(
                        animation: _orbitController,
                        size: orbitSize,
                      ),
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
                          onConfirm: _hasDeviceFix && _selectedPoint.isValid
                              ? _confirmLocation
                              : null,
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

class _OrbitAnimation extends StatelessWidget {
  const _OrbitAnimation({required this.animation, required this.size});

  final Animation<double> animation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: size + 36,
      height: size + 36,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final pulse = 0.5 + math.sin(animation.value * math.pi * 2) * 0.5;
          return Transform.scale(
            scale: 1 + (pulse * 0.018),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(
                      alpha: isDark ? 0.19 : 0.17,
                    ),
                    blurRadius: 42,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.42),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.66),
                        ),
                      ),
                      child: CustomPaint(
                        painter: _OrbitPainter(
                          progress: animation.value,
                          accent: colors.accent,
                          isDark: isDark,
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
          );
        },
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({
    required this.progress,
    required this.accent,
    required this.isDark,
  });

  final double progress;
  final Color accent;
  final bool isDark;

  static const _crystalShards = <_CrystalShard>[
    _CrystalShard(
      anchor: Offset(-0.68, 0.42),
      size: 0.17,
      sides: 6,
      rotation: 0.22,
      speed: 0.54,
    ),
    _CrystalShard(
      anchor: Offset(-0.48, 0.05),
      size: 0.19,
      sides: 7,
      rotation: 0.64,
      speed: 0.48,
    ),
    _CrystalShard(
      anchor: Offset(-0.34, -0.04),
      size: 0.12,
      sides: 6,
      rotation: 0.08,
      speed: 0.72,
    ),
    _CrystalShard(
      anchor: Offset(-0.18, 0.06),
      size: 0.16,
      sides: 7,
      rotation: 0.42,
      speed: 0.58,
    ),
    _CrystalShard(
      anchor: Offset(-0.02, 0.16),
      size: 0.11,
      sides: 6,
      rotation: 0.74,
      speed: 0.68,
    ),
    _CrystalShard(
      anchor: Offset(0.14, 0.04),
      size: 0.15,
      sides: 6,
      rotation: 0.18,
      speed: 0.62,
    ),
    _CrystalShard(
      anchor: Offset(0.30, 0.14),
      size: 0.13,
      sides: 7,
      rotation: 0.55,
      speed: 0.52,
    ),
    _CrystalShard(
      anchor: Offset(0.50, 0.25),
      size: 0.17,
      sides: 6,
      rotation: 0.36,
      speed: 0.44,
    ),
    _CrystalShard(
      anchor: Offset(0.37, 0.48),
      size: 0.10,
      sides: 6,
      rotation: 0.82,
      speed: 0.70,
    ),
    _CrystalShard(
      anchor: Offset(0.13, 0.58),
      size: 0.18,
      sides: 7,
      rotation: 0.24,
      speed: 0.50,
    ),
    _CrystalShard(
      anchor: Offset(-0.15, 0.55),
      size: 0.20,
      sides: 6,
      rotation: 0.70,
      speed: 0.46,
    ),
    _CrystalShard(
      anchor: Offset(-0.32, 0.38),
      size: 0.13,
      sides: 6,
      rotation: 0.48,
      speed: 0.66,
    ),
    _CrystalShard(
      anchor: Offset(-0.54, -0.34),
      size: 0.08,
      sides: 6,
      rotation: 0.16,
      speed: 0.80,
    ),
    _CrystalShard(
      anchor: Offset(-0.28, -0.42),
      size: 0.07,
      sides: 6,
      rotation: 0.58,
      speed: 0.78,
    ),
    _CrystalShard(
      anchor: Offset(0.04, -0.45),
      size: 0.09,
      sides: 7,
      rotation: 0.26,
      speed: 0.74,
    ),
    _CrystalShard(
      anchor: Offset(0.42, -0.35),
      size: 0.08,
      sides: 6,
      rotation: 0.62,
      speed: 0.76,
    ),
    _CrystalShard(
      anchor: Offset(0.66, -0.18),
      size: 0.07,
      sides: 6,
      rotation: 0.04,
      speed: 0.82,
    ),
    _CrystalShard(
      anchor: Offset(-0.52, 0.78),
      size: 0.07,
      sides: 6,
      rotation: 0.32,
      speed: 0.86,
    ),
    _CrystalShard(
      anchor: Offset(-0.08, 0.84),
      size: 0.18,
      sides: 6,
      rotation: 0.50,
      speed: 0.40,
    ),
    _CrystalShard(
      anchor: Offset(0.64, 0.67),
      size: 0.07,
      sides: 6,
      rotation: 0.22,
      speed: 0.84,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final turn = progress * math.pi * 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: isDark ? 0.17 : 0.22);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: isDark ? 0.20 : 0.26),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.95));

    canvas.drawCircle(center, radius * 0.92, glowPaint);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.24);
    canvas.scale(1, 0.46);
    canvas.drawCircle(Offset.zero, radius * 0.66, ringPaint);
    canvas.restore();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turn * 0.82 + 0.64);
    canvas.scale(1, 0.34);
    canvas.drawCircle(Offset.zero, radius * 0.78, ringPaint);
    canvas.restore();

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE1E0FF).withValues(alpha: isDark ? 0.12 : 0.46),
          accent.withValues(alpha: isDark ? 0.20 : 0.22),
          Colors.transparent,
        ],
        stops: const [0, 0.48, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.62));
    canvas.drawCircle(center, radius * 0.54, corePaint);

    for (var i = 0; i < _crystalShards.length; i++) {
      final shard = _crystalShards[i];
      final phase = turn * (1.2 + shard.speed) + shard.rotation;
      final drift = Offset(
        math.cos(phase) * radius * 0.045,
        math.sin(phase * 1.2) * radius * 0.052,
      );
      final shardCenter =
          center +
          Offset(shard.anchor.dx * radius, shard.anchor.dy * radius) +
          drift;
      final shardRadius =
          radius * shard.size * (0.96 + math.sin(phase + i) * 0.05);
      _drawCrystal(
        canvas,
        center: shardCenter,
        radius: shardRadius,
        sides: shard.sides,
        rotation: shard.rotation + turn * (0.36 + shard.speed * 0.18),
        seed: i,
      );
    }

    final centerDot = Paint()
      ..color = accent.withValues(alpha: 0.92)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    canvas.drawCircle(center, radius * 0.035, centerDot);
  }

  void _drawCrystal(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required int sides,
    required double rotation,
    required int seed,
  }) {
    final vertices = <Offset>[];
    final stretchX = 0.92 + ((seed % 4) * 0.05);
    final stretchY = 0.82 + ((seed % 5) * 0.045);

    for (var i = 0; i < sides; i++) {
      final angle = rotation + (math.pi * 2 * i / sides);
      final irregularity = 0.78 + (((seed * 17 + i * 29) % 38) / 100);
      vertices.add(
        center +
            Offset(
              math.cos(angle) * radius * irregularity * stretchX,
              math.sin(angle) * radius * irregularity * stretchY,
            ),
      );
    }

    final polygon = Path()..moveTo(vertices.first.dx, vertices.first.dy);
    for (final vertex in vertices.skip(1)) {
      polygon.lineTo(vertex.dx, vertex.dy);
    }
    polygon.close();

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.18 : 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    canvas.drawPath(polygon.shift(const Offset(1.8, 2.4)), shadowPaint);

    final light = const Offset(-0.58, -0.82);
    final dark = const Color(0xFF26206F);
    final mid = const Color(0xFF4F46E5);
    final bright = const Color(0xFF858BFF);
    final icy = const Color(0xFFC8D7FF);
    final baseAlpha = isDark ? 0.94 : 0.82;

    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      final edgeVector = Offset(
        ((a.dx + b.dx) / 2) - center.dx,
        ((a.dy + b.dy) / 2) - center.dy,
      );
      final dot =
          ((edgeVector.dx * light.dx) + (edgeVector.dy * light.dy)) /
          math.max(1, edgeVector.distance * light.distance);
      final lit = (((dot + 1) / 2) * 0.9 + 0.06).clamp(0.0, 1.0).toDouble();
      var facetColor = Color.lerp(dark, bright, lit)!;
      if ((seed + i) % 5 == 0) {
        facetColor = Color.lerp(facetColor, icy, 0.46)!;
      } else if ((seed + i) % 3 == 0) {
        facetColor = Color.lerp(facetColor, mid, 0.36)!;
      }

      final facet = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..close();
      canvas.drawPath(
        facet,
        Paint()..color = facetColor.withValues(alpha: baseAlpha),
      );
    }

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, radius * 0.045)
      ..color = const Color(0xFF151A62).withValues(alpha: isDark ? 0.42 : 0.24);
    canvas.drawPath(polygon, outlinePaint);

    final glint = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(vertices.first.dx, vertices.first.dy)
      ..lineTo(vertices[1].dx, vertices[1].dy)
      ..close();
    canvas.drawPath(
      glint,
      Paint()..color = Colors.white.withValues(alpha: isDark ? 0.18 : 0.28),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.isDark != isDark;
  }
}

class _CrystalShard {
  const _CrystalShard({
    required this.anchor,
    required this.size,
    required this.sides,
    required this.rotation,
    required this.speed,
  });

  final Offset anchor;
  final double size;
  final int sides;
  final double rotation;
  final double speed;
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
    required this.selectedPoint,
    required this.onConfirm,
    this.error,
  });

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
            label: 'Use current orbit',
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

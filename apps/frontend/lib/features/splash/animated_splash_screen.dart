import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:space_mobile/theme.dart';

/// Animated futuristic splash / loading screen for the Space application.
/// Features a cluster of 3D low-poly crystals floating and orbiting inside a soft circular glow.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({
    super.key,
    this.title = 'Finding your\norbit...',
    this.subtitle = 'Connecting you to judgment-free\nspaces nearby.',
  });

  final String title;
  final String subtitle;

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_CrystalData> _crystals;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _crystals = _generateCrystals();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_CrystalData> _generateCrystals() {
    final rand = math.Random(42); // Deterministic seed for reproducible aesthetic composition
    final list = <_CrystalData>[];

    const int count = 28;
    for (int i = 0; i < count; i++) {
      final orbitRx = 35.0 + rand.nextDouble() * 85.0;
      final orbitRy = 25.0 + rand.nextDouble() * 65.0;
      final orbitAngleOffset = rand.nextDouble() * 2 * math.pi;
      final orbitSpeed = (rand.nextBool() ? 1 : -1) * (0.3 + rand.nextDouble() * 0.7);

      final floatAmpX = 4.0 + rand.nextDouble() * 8.0;
      final floatAmpY = 6.0 + rand.nextDouble() * 12.0;
      final floatAmpZ = 15.0 + rand.nextDouble() * 25.0;
      final floatFreq = 1.0 + rand.nextDouble() * 2.0;
      final floatPhase = rand.nextDouble() * 2 * math.pi;

      final rotSpeedX = (rand.nextDouble() - 0.5) * 2.2;
      final rotSpeedY = (rand.nextDouble() - 0.5) * 2.5;
      final rotSpeedZ = (rand.nextDouble() - 0.5) * 1.8;

      final size = 7.0 + rand.nextDouble() * 11.0;
      final crystalType = rand.nextInt(3); // 0: Diamond Octahedron, 1: Elongated Crystal, 2: Poly Fragment

      list.add(_CrystalData(
        orbitRx: orbitRx,
        orbitRy: orbitRy,
        orbitAngleOffset: orbitAngleOffset,
        orbitSpeed: orbitSpeed,
        floatAmpX: floatAmpX,
        floatAmpY: floatAmpY,
        floatAmpZ: floatAmpZ,
        floatFreq: floatFreq,
        floatPhase: floatPhase,
        rotSpeedX: rotSpeedX,
        rotSpeedY: rotSpeedY,
        rotSpeedZ: rotSpeedZ,
        size: size,
        crystalType: crystalType,
        colorIndex: i % 4,
      ));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = SpaceColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final orbitAreaSize = math.min(size.width * 0.78, 300.0);

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          // Background Atmospheric Radial Glow
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.25),
                    radius: 0.85,
                    colors: isDark
                        ? [
                            const Color(0xFF0F172A).withValues(alpha: 0.4),
                            colors.background,
                          ]
                        : [
                            const Color(0xFFEEF2FF).withValues(alpha: 0.7),
                            colors.background,
                          ],
                  ),
                ),
              ),
            ),
          ),

          // Main Centered Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // 1. Soft Circular Orbital Area + 3D Floating Crystals
                  Center(
                    child: SizedBox(
                      width: orbitAreaSize,
                      height: orbitAreaSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Soft Ambient Circle Background
                          Container(
                            width: orbitAreaSize * 0.88,
                            height: orbitAreaSize * 0.88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: isDark
                                    ? [
                                        const Color(0xFF101928).withValues(alpha: 0.65),
                                        const Color(0xFF0B1017).withValues(alpha: 0.2),
                                        Colors.transparent,
                                      ]
                                    : [
                                        const Color(0xFFEEF2FF).withValues(alpha: 0.85),
                                        const Color(0xFFE0E7FF).withValues(alpha: 0.35),
                                        Colors.transparent,
                                      ],
                                stops: const [0.0, 0.7, 1.0],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark
                                      ? const Color(0xFF3B82F6).withValues(alpha: 0.08)
                                      : const Color(0xFF818CF8).withValues(alpha: 0.15),
                                  blurRadius: 32,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),

                          // Ethereal subtle orbital ring
                          Container(
                            width: orbitAreaSize * 0.94,
                            height: orbitAreaSize * 0.94,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF3B82F6).withValues(alpha: 0.1)
                                    : const Color(0xFF818CF8).withValues(alpha: 0.18),
                                width: 1.0,
                              ),
                            ),
                          ),

                          // Continuous Animated 3D Crystals CustomPainter
                          RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) {
                                return CustomPaint(
                                  size: Size(orbitAreaSize, orbitAreaSize),
                                  painter: _CrystalsPainter(
                                    t: _controller.value * 2 * math.pi,
                                    crystals: _crystals,
                                    isDark: isDark,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // 2. Main Title ("Finding your orbit...")
                  ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                const Color(0xFFAFC5FF),
                                const Color(0xFF8B5CF6),
                              ]
                            : [
                                const Color(0xFF3B82F6),
                                const Color(0xFF6366F1),
                                const Color(0xFF8B5CF6),
                              ],
                      ).createShader(bounds);
                    },
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: SpaceTypography.headingLarge(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: Colors.white,
                      ).copyWith(height: 1.15),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 3. Subtitle ("Connecting you to judgment-free spaces nearby.")
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: SpaceTypography.bodyLarge(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFFA1AAB8)
                          : const Color(0xFF475569),
                      height: 1.45,
                    ),
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrystalData {
  _CrystalData({
    required this.orbitRx,
    required this.orbitRy,
    required this.orbitAngleOffset,
    required this.orbitSpeed,
    required this.floatAmpX,
    required this.floatAmpY,
    required this.floatAmpZ,
    required this.floatFreq,
    required this.floatPhase,
    required this.rotSpeedX,
    required this.rotSpeedY,
    required this.rotSpeedZ,
    required this.size,
    required this.crystalType,
    required this.colorIndex,
  });

  final double orbitRx;
  final double orbitRy;
  final double orbitAngleOffset;
  final double orbitSpeed;
  final double floatAmpX;
  final double floatAmpY;
  final double floatAmpZ;
  final double floatFreq;
  final double floatPhase;
  final double rotSpeedX;
  final double rotSpeedY;
  final double rotSpeedZ;
  final double size;
  final int crystalType;
  final int colorIndex;
}

class _CrystalsPainter extends CustomPainter {
  _CrystalsPainter({
    required this.t,
    required this.crystals,
    required this.isDark,
  });

  final double t;
  final List<_CrystalData> crystals;
  final bool isDark;

  // Soft futuristic palette for faceted stones
  static const _lightPalettes = [
    [Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFA5B4FC), Color(0xFFC7D2FE)],
    [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFA5B4FC)],
    [Color(0xFF8B5CF6), Color(0xFFA78BFA), Color(0xFFC4B5FD), Color(0xFFDDD6FE)],
    [Color(0xFF3B82F6), Color(0xFF60A5FA), Color(0xFF93C5FD), Color(0xFFBFDBFE)],
  ];

  static const _darkPalettes = [
    [Color(0xFF4338CA), Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFA5B4FC)],
    [Color(0xFF3B82F6), Color(0xFF60A5FA), Color(0xFF93C5FD), Color(0xFFBFDBFE)],
    [Color(0xFF7C3AED), Color(0xFF8B5CF6), Color(0xFFA78BFA), Color(0xFFC4B5FD)],
    [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF60A5FA), Color(0xFFAFC5FF)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. Calculate 3D positions for all stones
    final renderedStones = <_RenderedStone>[];

    for (final c in crystals) {
      final angle = c.orbitAngleOffset + t * c.orbitSpeed;
      final floatTime = t * c.floatFreq + c.floatPhase;

      // 3D position
      final posX = math.cos(angle) * c.orbitRx + math.sin(floatTime) * c.floatAmpX;
      final posY = math.sin(angle) * c.orbitRy + math.cos(floatTime * 0.8) * c.floatAmpY;
      final posZ = math.sin(angle * 1.5) * 40.0 + math.sin(floatTime * 1.2) * c.floatAmpZ;

      // Rotation angles
      final rotX = t * c.rotSpeedX;
      final rotY = t * c.rotSpeedY;
      final rotZ = t * c.rotSpeedZ;

      // Depth projection
      const cameraDist = 220.0;
      final scale = cameraDist / (cameraDist + posZ);
      final screenX = cx + posX * scale;
      final screenY = cy + posY * scale;

      renderedStones.add(_RenderedStone(
        screenX: screenX,
        screenY: screenY,
        depthZ: posZ,
        scale: scale,
        rotX: rotX,
        rotY: rotY,
        rotZ: rotZ,
        data: c,
      ));
    }

    // 2. Sort by depth (back to front painter's algorithm)
    renderedStones.sort((a, b) => b.depthZ.compareTo(a.depthZ));

    // 3. Draw each crystal
    final lightDir = _normalize3D(-0.5, -0.6, 0.6);
    final palettes = isDark ? _darkPalettes : _lightPalettes;

    for (final stone in renderedStones) {
      final palette = palettes[stone.data.colorIndex];
      _draw3DCrystal(
        canvas: canvas,
        cx: stone.screenX,
        cy: stone.screenY,
        size: stone.data.size * stone.scale,
        rotX: stone.rotX,
        rotY: stone.rotY,
        rotZ: stone.rotZ,
        type: stone.data.crystalType,
        palette: palette,
        lightDir: lightDir,
        opacity: (0.75 + (stone.scale - 0.8) * 0.4).clamp(0.4, 1.0),
      );
    }
  }

  void _draw3DCrystal({
    required Canvas canvas,
    required double cx,
    required double cy,
    required double size,
    required double rotX,
    required double rotY,
    required double rotZ,
    required int type,
    required List<Color> palette,
    required List<double> lightDir,
    required double opacity,
  }) {
    // Generate 3D Polyhedron geometry based on type
    final model = _getGeometry(type, size);
    final vertices = model.vertices;
    final faces = model.faces;

    // Rotate vertices
    final rotated = <List<double>>[];
    for (final v in vertices) {
      rotated.add(_rotate3D(v[0], v[1], v[2], rotX, rotY, rotZ));
    }

    // Sort faces by average z depth
    final faceOrder = <_FaceInfo>[];
    for (int i = 0; i < faces.length; i++) {
      final face = faces[i];
      final v0 = rotated[face[0]];
      final v1 = rotated[face[1]];
      final v2 = rotated[face[2]];

      final avgZ = (v0[2] + v1[2] + v2[2]) / 3;

      // Normal vector calculation
      final ax = v1[0] - v0[0];
      final ay = v1[1] - v0[1];
      final az = v1[2] - v0[2];

      final bx = v2[0] - v0[0];
      final by = v2[1] - v0[1];
      final bz = v2[2] - v0[2];

      final nx = ay * bz - az * by;
      final ny = az * bx - ax * bz;
      final nz = ax * by - ay * bx;

      // Back-face culling
      if (nz > 0) {
        final norm = _normalize3D(nx, ny, nz);
        final dot = (norm[0] * lightDir[0] + norm[1] * lightDir[1] + norm[2] * lightDir[2]).clamp(0.0, 1.0);
        faceOrder.add(_FaceInfo(index: i, avgZ: avgZ, brightness: dot));
      }
    }

    faceOrder.sort((a, b) => a.avgZ.compareTo(b.avgZ));

    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = (isDark ? Colors.white : Colors.indigo).withValues(alpha: 0.18 * opacity);

    for (final fi in faceOrder) {
      final face = faces[fi.index];
      final path = Path();
      for (int k = 0; k < face.length; k++) {
        final v = rotated[face[k]];
        final px = cx + v[0];
        final py = cy + v[1];
        if (k == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();

      // Shaded color selection based on facet angle
      final colorIdx = (fi.brightness * (palette.length - 1)).round().clamp(0, palette.length - 1);
      paint.color = palette[colorIdx].withValues(alpha: opacity);

      canvas.drawPath(path, paint);
      canvas.drawPath(path, strokePaint);
    }
  }

  _Geometry _getGeometry(int type, double s) {
    if (type == 0) {
      // Octahedral Diamond Crystal
      final vertices = [
        [0.0, -s * 1.3, 0.0],  // 0 Top
        [-s * 0.9, 0.0, -s * 0.7], // 1 Front-Left
        [s * 0.9, 0.0, -s * 0.7],  // 2 Front-Right
        [s * 0.7, 0.0, s * 0.9],   // 3 Back-Right
        [-s * 0.7, 0.0, s * 0.9],  // 4 Back-Left
        [0.0, s * 1.3, 0.0],   // 5 Bottom
      ];
      final faces = [
        [0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1], // Top pyramid
        [5, 2, 1], [5, 3, 2], [5, 4, 3], [5, 1, 4], // Bottom pyramid
      ];
      return _Geometry(vertices, faces);
    } else if (type == 1) {
      // Elongated Hexagonal Crystal Prism
      final vertices = [
        [0.0, -s * 1.4, 0.0],   // 0 Top Apex
        [-s * 0.8, -s * 0.4, -s * 0.6], // 1
        [s * 0.8, -s * 0.4, -s * 0.6],  // 2
        [s * 0.6, -s * 0.4, s * 0.8],   // 3
        [-s * 0.6, -s * 0.4, s * 0.8],  // 4
        [-s * 0.7, s * 0.9, -s * 0.5],  // 5
        [s * 0.7, s * 0.9, -s * 0.5],   // 6
        [s * 0.5, s * 0.9, s * 0.7],    // 7
        [-s * 0.5, s * 0.9, s * 0.7],   // 8
        [0.0, s * 1.4, 0.0],    // 9 Bottom Apex
      ];
      final faces = [
        [0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1], // Top Cap
        [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 8, 4], [4, 8, 5, 1], // Sides
        [9, 6, 5], [9, 7, 6], [9, 8, 7], [9, 5, 8], // Bottom Cap
      ];
      return _Geometry(vertices, faces);
    } else {
      // Asymmetrical Low-Poly Rock/Fragment
      final vertices = [
        [-s * 0.4, -s * 1.0, 0.0],  // 0 Top
        [-s * 1.1, -s * 0.2, -s * 0.6], // 1
        [s * 0.9, -s * 0.4, -s * 0.8],  // 2
        [s * 1.0, 0.2, s * 0.7],   // 3
        [-s * 0.8, 0.4, s * 0.9],  // 4
        [0.2, s * 1.1, -s * 0.3],  // 5 Bottom
      ];
      final faces = [
        [0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1],
        [5, 2, 1], [5, 3, 2], [5, 4, 3], [5, 1, 4],
      ];
      return _Geometry(vertices, faces);
    }
  }

  List<double> _rotate3D(double x, double y, double z, double rx, double ry, double rz) {
    // Rotate X
    final cosX = math.cos(rx);
    final sinX = math.sin(rx);
    final y1 = y * cosX - z * sinX;
    final z1 = y * sinX + z * cosX;

    // Rotate Y
    final cosY = math.cos(ry);
    final sinY = math.sin(ry);
    final x2 = x * cosY + z1 * sinY;
    final z2 = -x * sinY + z1 * cosY;

    // Rotate Z
    final cosZ = math.cos(rz);
    final sinZ = math.sin(rz);
    final x3 = x2 * cosZ - y1 * sinZ;
    final y3 = x2 * sinZ + y1 * cosZ;

    return [x3, y3, z2];
  }

  List<double> _normalize3D(double x, double y, double z) {
    final len = math.sqrt(x * x + y * y + z * z);
    if (len == 0) return [0, 0, 1];
    return [x / len, y / len, z / len];
  }

  @override
  bool shouldRepaint(covariant _CrystalsPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.isDark != isDark;
  }
}

class _RenderedStone {
  _RenderedStone({
    required this.screenX,
    required this.screenY,
    required this.depthZ,
    required this.scale,
    required this.rotX,
    required this.rotY,
    required this.rotZ,
    required this.data,
  });

  final double screenX;
  final double screenY;
  final double depthZ;
  final double scale;
  final double rotX;
  final double rotY;
  final double rotZ;
  final _CrystalData data;
}

class _Geometry {
  _Geometry(this.vertices, this.faces);
  final List<List<double>> vertices;
  final List<List<int>> faces;
}

class _FaceInfo {
  _FaceInfo({required this.index, required this.avgZ, required this.brightness});
  final int index;
  final double avgZ;
  final double brightness;
}

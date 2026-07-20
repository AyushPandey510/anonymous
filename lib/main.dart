import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:space_mobile/features/location/domain/geofence.dart';
import 'package:space_mobile/features/location/domain/geofence_validator.dart';
import 'package:space_mobile/features/location/domain/geo_point.dart';
import 'package:space_mobile/features/location/domain/location_fix.dart';
import 'package:space_mobile/features/location/presentation/interactive_geofence_map.dart';

void main() {
  runApp(const SpaceApp());
}

class SpaceApp extends StatelessWidget {
  const SpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Space',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SpaceColors.black,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: SpaceColors.accent,
          surface: SpaceColors.surface,
          onSurface: SpaceColors.white,
        ),
        useMaterial3: true,
      ),
      home: const SpaceShell(),
    );
  }
}

class SpaceShell extends StatefulWidget {
  const SpaceShell({super.key});

  @override
  State<SpaceShell> createState() => _SpaceShellState();
}

class _SpaceShellState extends State<SpaceShell> {
  int _tab = 0;
  SpaceRoom? _activeRoom;

  final _rooms = const [
    SpaceRoom(
      name: 'Startup Engineering',
      description: 'Deploys, incidents, quiet wins.',
      distance: '20m away',
      active: 18,
      inside: true,
      locked: false,
    ),
    SpaceRoom(
      name: 'Design Team',
      description: 'Crits, prototypes, product taste.',
      distance: '8m away',
      active: 6,
      inside: true,
      locked: false,
    ),
    SpaceRoom(
      name: 'Leadership',
      description: 'Invitation required.',
      distance: 'Inside building',
      active: 4,
      inside: true,
      locked: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _activeRoom = _rooms.first;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        rooms: _rooms,
        activeRoom: _activeRoom!,
        onJoin: _joinRoom,
        onCreate: () => setState(() => _tab = 2),
      ),
      ChatScreen(room: _activeRoom!),
      CreateSpaceScreen(
        onCreated: (room) {
          setState(() {
            _activeRoom = room;
            _tab = 1;
          });
        },
      ),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: pages[_tab],
      ),
      bottomNavigationBar: SpaceNavBar(
        selectedIndex: _tab,
        onSelected: (index) => setState(() => _tab = index),
      ),
    );
  }

  void _joinRoom(SpaceRoom room) async {
    if (room.locked) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        pageBuilder: (_, animation, _) {
          return FadeTransition(
            opacity: animation,
            child: VerifyOverlay(roomName: room.name),
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      _activeRoom = room;
      _tab = 1;
    });
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.rooms,
    required this.activeRoom,
    required this.onJoin,
    required this.onCreate,
  });

  final List<SpaceRoom> rooms;
  final SpaceRoom activeRoom;
  final ValueChanged<SpaceRoom> onJoin;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
        children: [
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Good evening',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: onCreate,
                style: IconButton.styleFrom(
                  backgroundColor: SpaceColors.card,
                  foregroundColor: SpaceColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 22),
          HeroPresenceCard(room: activeRoom, onJoin: () => onJoin(activeRoom)),
          const SizedBox(height: 30),
          const SectionLabel('Nearby Spaces'),
          const SizedBox(height: 12),
          for (final room in rooms) ...[
            SpaceCard(room: room, onTap: () => onJoin(room)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class HeroPresenceCard extends StatelessWidget {
  const HeroPresenceCard({super.key, required this.room, required this.onJoin});

  final SpaceRoom room;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2027), Color(0xFF121315)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: SpaceColors.accent.withValues(alpha: 0.10),
            blurRadius: 42,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GeofencePill(status: PresenceStatus.inside),
          const SizedBox(height: 28),
          Text(
            room.name,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${room.active} people active',
            style: const TextStyle(color: SpaceColors.secondary, fontSize: 15),
          ),
          const SizedBox(height: 24),
          SpaceButton(
            label: 'Join Space',
            icon: Icons.arrow_forward_rounded,
            onPressed: onJoin,
          ),
        ],
      ),
    );
  }
}

class SpaceCard extends StatefulWidget {
  const SpaceCard({super.key, required this.room, required this.onTap});

  final SpaceRoom room;
  final VoidCallback onTap;

  @override
  State<SpaceCard> createState() => _SpaceCardState();
}

class _SpaceCardState extends State<SpaceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: SpaceColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              StatusDot(
                color: widget.room.locked
                    ? SpaceColors.disabled
                    : SpaceColors.accent,
                hollow: widget.room.locked,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.room.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.room.locked
                          ? 'Invitation required'
                          : widget.room.distance,
                      style: const TextStyle(
                        color: SpaceColors.secondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                widget.room.locked ? 'Locked' : '${widget.room.active} active',
                style: const TextStyle(
                  color: SpaceColors.secondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.room});

  final SpaceRoom room;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <ChatMessage>[
    const ChatMessage(
      name: 'Blue Panda',
      text: 'Finished deployment.',
      color: Color(0xFF4EA8FF),
      reactions: 12,
    ),
    const ChatMessage(
      name: 'Silent Fox',
      text: 'Did production recover?',
      color: Color(0xFF8B7CFF),
      reactions: 3,
    ),
    const ChatMessage(
      name: 'Coffee Bean',
      text: 'Yes. Error rate is flat again.',
      color: Color(0xFF37D399),
      reactions: 8,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: SpaceHeader(room: widget.room),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return AnimatedSlide(
                  offset: Offset(0, index == _messages.length - 1 ? 0 : 0),
                  duration: const Duration(milliseconds: 220),
                  child: MessageCard(message: _messages[index]),
                );
              },
            ),
          ),
          ChatComposer(
            controller: _controller,
            onSend: () {
              final text = _controller.text.trim();
              if (text.isEmpty) return;
              setState(() {
                _messages.add(
                  ChatMessage(
                    name: 'Quiet Nova',
                    text: text,
                    color: SpaceColors.accent,
                    reactions: 0,
                  ),
                );
                _controller.clear();
              });
            },
          ),
        ],
      ),
    );
  }
}

class SpaceHeader extends StatelessWidget {
  const SpaceHeader({super.key, required this.room});

  final SpaceRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SpaceColors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widgetRoomName(room.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    const GeofencePill(
                      status: PresenceStatus.inside,
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${room.active} active',
                      style: const TextStyle(
                        color: SpaceColors.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Leaving area in 12 min',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: SpaceColors.secondary,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

String widgetRoomName(String name) => name;

class MessageCard extends StatelessWidget {
  const MessageCard({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpaceColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: message.color),
              const SizedBox(width: 9),
              Text(
                message.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message.text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.35,
              color: SpaceColors.white,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TinyAction(
                icon: Icons.thumb_up_alt_outlined,
                label: '${message.reactions}',
              ),
              const SizedBox(width: 10),
              const TinyAction(icon: Icons.reply_rounded, label: 'Reply'),
            ],
          ),
        ],
      ),
    );
  }
}

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          decoration: BoxDecoration(
            color: SpaceColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Anonymous message...',
                    hintStyle: TextStyle(color: SpaceColors.disabled),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onSend,
                style: IconButton.styleFrom(
                  backgroundColor: SpaceColors.accent,
                  foregroundColor: SpaceColors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CreateSpaceScreen extends StatefulWidget {
  const CreateSpaceScreen({super.key, required this.onCreated});

  final ValueChanged<SpaceRoom> onCreated;

  @override
  State<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends State<CreateSpaceScreen> {
  final _nameController = TextEditingController(text: 'Engineering Team');
  final _latitudeController = TextEditingController(text: '12.971600');
  final _longitudeController = TextEditingController(text: '77.594600');
  final _accuracyController = TextEditingController(text: '18');
  final _validator = const GeofenceValidator();
  bool _isPrivate = false;
  double _radius = 120;
  GeoPoint _selectedPoint = const GeoPoint(
    latitude: 12.9716,
    longitude: 77.5946,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _accuracyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geofence = CircleGeofence(
      center: _selectedPoint,
      radiusMeters: _radius.round(),
    );
    final currentFix = LocationFix(
      point: _selectedPoint,
      accuracyMeters: double.tryParse(_accuracyController.text),
      capturedAt: DateTime.now().toUtc(),
    );
    final validation = _validator.validate(
      geofence: geofence,
      current: currentFix,
    );

    return SpaceScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 112),
        children: [
          const Text(
            'Create Space',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Four quiet steps. No admins after creation.',
            style: TextStyle(color: SpaceColors.secondary, fontSize: 15),
          ),
          const SizedBox(height: 24),
          StepCard(
            step: 'Step 1',
            title: 'Name',
            child: SpaceTextField(controller: _nameController),
          ),
          const SizedBox(height: 14),
          StepCard(
            step: 'Step 2',
            title: 'Visibility',
            child: Row(
              children: [
                Expanded(
                  child: ChoicePill(
                    label: 'Public',
                    selected: !_isPrivate,
                    onTap: () => setState(() => _isPrivate = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoicePill(
                    label: 'Private',
                    selected: _isPrivate,
                    onTap: () => setState(() => _isPrivate = true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          StepCard(
            step: 'Step 3',
            title: 'Location',
            child: Column(
              children: [
                InteractiveGeofenceMap(
                  point: _selectedPoint,
                  radiusMeters: _radius.round(),
                  validation: validation,
                  onPointChanged: _setSelectedPoint,
                  onAccuracyChanged: _setAccuracy,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: CoordinateField(
                        label: 'Latitude',
                        controller: _latitudeController,
                        onChanged: (_) => _syncCoordinates(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CoordinateField(
                        label: 'Longitude',
                        controller: _longitudeController,
                        onChanged: (_) => _syncCoordinates(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CoordinateField(
                  label: 'Accuracy meters',
                  controller: _accuracyController,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          StepCard(
            step: 'Step 4',
            title: 'Geofence',
            child: Column(
              children: [
                GeofenceDecisionPanel(validation: validation),
                const SizedBox(height: 12),
                Slider(
                  value: _radius,
                  min: CircleGeofence.minRadiusMeters.toDouble(),
                  max: CircleGeofence.maxRadiusMeters.toDouble(),
                  divisions:
                      CircleGeofence.maxRadiusMeters -
                      CircleGeofence.minRadiusMeters,
                  activeColor: SpaceColors.accent,
                  inactiveColor: SpaceColors.card,
                  onChanged: (value) => setState(() => _radius = value),
                ),
                Text(
                  '${_radius.round()}m radius',
                  style: const TextStyle(
                    color: SpaceColors.secondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SpaceButton(
            label: 'Create Space',
            icon: Icons.check_rounded,
            onPressed: () {
              if (!geofence.isValid || !validation.canParticipate) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_validationMessage(validation)),
                    backgroundColor: SpaceColors.card,
                  ),
                );
                return;
              }
              widget.onCreated(
                SpaceRoom(
                  name: _nameController.text.trim().isEmpty
                      ? 'Untitled Space'
                      : _nameController.text.trim(),
                  description: _isPrivate
                      ? 'Invitation required.'
                      : 'Created nearby.',
                  distance: 'Here',
                  active: 1,
                  inside: true,
                  locked: _isPrivate,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _setSelectedPoint(GeoPoint point) {
    setState(() {
      _selectedPoint = point;
      _latitudeController.text = point.latitude.toStringAsFixed(6);
      _longitudeController.text = point.longitude.toStringAsFixed(6);
    });
  }

  void _setAccuracy(double accuracyMeters) {
    setState(() {
      _accuracyController.text = accuracyMeters.toStringAsFixed(0);
    });
  }

  void _syncCoordinates() {
    final latitude = double.tryParse(_latitudeController.text);
    final longitude = double.tryParse(_longitudeController.text);
    if (latitude == null || longitude == null) {
      setState(() {});
      return;
    }
    setState(() {
      _selectedPoint = GeoPoint(latitude: latitude, longitude: longitude);
    });
  }

  String _validationMessage(GeofenceValidationResult validation) {
    return switch (validation.decision) {
      GeofenceDecision.inside => 'Location verified.',
      GeofenceDecision.nearBoundary =>
        'Location is near the boundary. Increase the radius or improve GPS accuracy.',
      GeofenceDecision.outside =>
        'Selected location is outside the current fix.',
      GeofenceDecision.lowAccuracy =>
        'Location accuracy is too low. Wait for a stronger GPS fix.',
      GeofenceDecision.rejected => 'The location fix was rejected.',
    };
  }
}

class ProductionMapPlaceholder extends StatelessWidget {
  const ProductionMapPlaceholder({
    super.key,
    required this.point,
    required this.radiusMeters,
    required this.validation,
    required this.onMove,
  });

  final GeoPoint point;
  final int radiusMeters;
  final GeofenceValidationResult validation;
  final void Function(double latitudeOffset, double longitudeOffset) onMove;

  @override
  Widget build(BuildContext context) {
    final circleSize =
        84 + (radiusMeters / CircleGeofence.maxRadiusMeters) * 96;
    return Container(
      height: 260,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _MapGrid()),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _decisionColor(
                  validation.decision,
                ).withValues(alpha: 0.08),
                border: Border.all(
                  color: _decisionColor(
                    validation.decision,
                  ).withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, -10),
              child: const Icon(
                Icons.location_pin,
                color: SpaceColors.accent,
                size: 42,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: MapChip(
              icon: Icons.search_rounded,
              label: 'Search ready',
              onTap: () {},
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: MapChip(
              icon: Icons.my_location_rounded,
              label: 'Re-center',
              onTap: () => onMove(0, 0),
              compact: true,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: SpaceColors.secondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                _NudgeButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  onTap: () => onMove(0.0001, 0),
                ),
                _NudgeButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: () => onMove(-0.0001, 0),
                ),
                _NudgeButton(
                  icon: Icons.keyboard_arrow_left_rounded,
                  onTap: () => onMove(0, -0.0001),
                ),
                _NudgeButton(
                  icon: Icons.keyboard_arrow_right_rounded,
                  onTap: () => onMove(0, 0.0001),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _decisionColor(GeofenceDecision decision) {
    return switch (decision) {
      GeofenceDecision.inside => SpaceColors.accent,
      GeofenceDecision.nearBoundary => const Color(0xFFF4C35C),
      GeofenceDecision.outside => const Color(0xFFFF6262),
      GeofenceDecision.lowAccuracy => const Color(0xFFF4C35C),
      GeofenceDecision.rejected => const Color(0xFFFF6262),
    };
  }
}

class _MapGrid extends StatelessWidget {
  const _MapGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MapGridPainter());
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: SpaceColors.card,
        foregroundColor: SpaceColors.secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class MapChip extends StatelessWidget {
  const MapChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 11,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: SpaceColors.card.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: SpaceColors.secondary),
            if (!compact) ...[
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: SpaceColors.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CoordinateField extends StatelessWidget {
  const CoordinateField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: SpaceColors.disabled, fontSize: 12),
        filled: true,
        fillColor: SpaceColors.surface,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: SpaceColors.accent),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class GeofenceDecisionPanel extends StatelessWidget {
  const GeofenceDecisionPanel({super.key, required this.validation});

  final GeofenceValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final color = ProductionMapPlaceholder._decisionColor(validation.decision);
    final label = switch (validation.decision) {
      GeofenceDecision.inside => 'Inside',
      GeofenceDecision.nearBoundary => 'Near boundary',
      GeofenceDecision.outside => 'Outside',
      GeofenceDecision.lowAccuracy => 'Low accuracy',
      GeofenceDecision.rejected => 'Rejected',
    };
    final confidence = switch (validation.confidence) {
      LocationConfidence.high => 'High confidence',
      LocationConfidence.medium => 'Medium confidence',
      LocationConfidence.low => 'Low confidence',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.radar_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${validation.distanceMeters.toStringAsFixed(1)}m from center • $confidence',
                  style: const TextStyle(
                    color: SpaceColors.secondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VerifyOverlay extends StatefulWidget {
  const VerifyOverlay({super.key, required this.roomName});

  final String roomName;

  @override
  State<VerifyOverlay> createState() => _VerifyOverlayState();
}

class _VerifyOverlayState extends State<VerifyOverlay> {
  int _step = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (_step >= 3) {
        timer.cancel();
        Future<void>.delayed(const Duration(milliseconds: 450), () {
          if (mounted) Navigator.of(context).pop();
        });
      } else {
        setState(() => _step++);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Finding Spaces',
      'Checking boundary',
      'Verified',
      'Entering Space',
    ];
    return Center(
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: SpaceColors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 40,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedPulse(active: _step < 2),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Text(
                labels[_step],
                key: ValueKey(_step),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              widget.roomName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SpaceColors.secondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpaceScaffold extends StatelessWidget {
  const SpaceScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.2,
          colors: [Color(0xFF13211F), SpaceColors.black],
          stops: [0, 0.58],
        ),
      ),
      child: child,
    );
  }
}

class SpaceNavBar extends StatelessWidget {
  const SpaceNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SpaceColors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: SpaceColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                NavItem(
                  icon: Icons.radar_rounded,
                  label: 'Presence',
                  selected: selectedIndex == 0,
                  onTap: () => onSelected(0),
                ),
                NavItem(
                  icon: Icons.forum_outlined,
                  label: 'Chat',
                  selected: selectedIndex == 1,
                  onTap: () => onSelected(1),
                ),
                NavItem(
                  icon: Icons.add_location_alt_outlined,
                  label: 'Create',
                  selected: selectedIndex == 2,
                  onTap: () => onSelected(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? SpaceColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? SpaceColors.accent : SpaceColors.disabled,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? SpaceColors.white : SpaceColors.disabled,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GeofencePill extends StatelessWidget {
  const GeofencePill({super.key, required this.status, this.compact = false});

  final PresenceStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final data = switch (status) {
      PresenceStatus.inside => (
        'Inside Space',
        SpaceColors.accent,
        Icons.verified_rounded,
      ),
      PresenceStatus.leaving => (
        'Leaving Soon',
        Color(0xFFF4C35C),
        Icons.schedule_rounded,
      ),
      PresenceStatus.outside => (
        'Outside',
        Color(0xFFFF6262),
        Icons.location_off_rounded,
      ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: data.$2.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: data.$2.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.$3, size: compact ? 13 : 15, color: data.$2),
          const SizedBox(width: 6),
          Text(
            data.$1,
            style: TextStyle(
              color: data.$2,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SpaceButton extends StatelessWidget {
  const SpaceButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: SpaceColors.accent,
        foregroundColor: SpaceColors.black,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: SpaceColors.secondary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.hollow = false});

  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: hollow ? Colors.transparent : color,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.6),
      ),
    );
  }
}

class TinyAction extends StatelessWidget {
  const TinyAction({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SpaceColors.secondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: SpaceColors.secondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
  });

  final String step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SpaceColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step,
            style: const TextStyle(color: SpaceColors.disabled, fontSize: 12),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class SpaceTextField extends StatelessWidget {
  const SpaceTextField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true,
        fillColor: SpaceColors.surface,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(18),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: SpaceColors.accent),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? SpaceColors.accent.withValues(alpha: 0.14)
              : SpaceColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? SpaceColors.accent
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StatusDot(
              color: selected ? SpaceColors.accent : SpaceColors.disabled,
              hollow: !selected,
            ),
            const SizedBox(width: 9),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class RadiusPreview extends StatelessWidget {
  const RadiusPreview({super.key, required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = 74 + (radius / 300) * 88;
    return Container(
      height: 190,
      width: double.infinity,
      decoration: BoxDecoration(
        color: SpaceColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SpaceColors.accent.withValues(alpha: 0.08),
                border: Border.all(
                  color: SpaceColors.accent.withValues(alpha: 0.25),
                ),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: SpaceColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedPulse extends StatefulWidget {
  const AnimatedPulse({super.key, required this.active});

  final bool active;

  @override
  State<AnimatedPulse> createState() => _AnimatedPulseState();
}

class _AnimatedPulseState extends State<AnimatedPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = widget.active ? _controller.value : 1.0;
        final scale = 1 + (math.sin(value * math.pi) * 0.18);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SpaceColors.accent.withValues(alpha: 0.12),
              border: Border.all(
                color: SpaceColors.accent.withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.location_searching_rounded,
              color: SpaceColors.accent,
              size: 30,
            ),
          ),
        );
      },
    );
  }
}

class SpaceRoom {
  const SpaceRoom({
    required this.name,
    required this.description,
    required this.distance,
    required this.active,
    required this.inside,
    required this.locked,
  });

  final String name;
  final String description;
  final String distance;
  final int active;
  final bool inside;
  final bool locked;
}

class ChatMessage {
  const ChatMessage({
    required this.name,
    required this.text,
    required this.color,
    required this.reactions,
  });

  final String name;
  final String text;
  final Color color;
  final int reactions;
}

enum PresenceStatus { inside, leaving, outside }

class SpaceColors {
  static const black = Color(0xFF0B0B0C);
  static const surface = Color(0xFF151518);
  static const card = Color(0xFF1C1C20);
  static const white = Color(0xFFFFFFFF);
  static const secondary = Color(0xFFB4B4BC);
  static const disabled = Color(0xFF6E6E78);
  static const accent = Color(0xFF37D399);
}

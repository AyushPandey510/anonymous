import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:space_mobile/features/location/domain/geofence.dart';
import 'package:space_mobile/features/location/domain/geofence_validator.dart';
import 'package:space_mobile/features/location/domain/geo_point.dart';
import 'package:space_mobile/features/location/domain/location_fix.dart';
import 'package:space_mobile/features/location/presentation/location_selection_screen.dart';
import 'package:space_mobile/services/api_client.dart';
import 'package:space_mobile/services/api_service.dart';
import 'package:space_mobile/services/auth_service.dart';

void main() {
  runApp(const SpaceApp());
}

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

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
      home: const AppLoader(),
    );
  }
}

class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  final _client = ApiClient(apiBaseUrl);
  late final AuthService _auth;
  late final ApiService _api;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = AuthService(_client);
    _api = ApiService(_client);
    _init();
  }

  Future<void> _init() async {
    try {
      await _auth.init();
      final loggedIn = await _auth.ensureLoggedIn();
      if (!mounted) return;
      if (loggedIn) {
        setState(() => _ready = true);
      } else {
        setState(() => _error = 'Could not connect to server');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: SpaceColors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 48, color: SpaceColors.disabled),
                const SizedBox(height: 16),
                Text(_error!,
                    style: const TextStyle(color: SpaceColors.secondary)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _ready = false;
                    });
                    _init();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const Scaffold(
        backgroundColor: SpaceColors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SpaceShell(api: _api, auth: _auth);
  }
}

enum AppScreen { location, discovery, chat }

class SpaceShell extends StatefulWidget {
  const SpaceShell({super.key, required this.api, required this.auth});

  final ApiService api;
  final AuthService auth;

  @override
  State<SpaceShell> createState() => _SpaceShellState();
}

class _SpaceShellState extends State<SpaceShell> {
  AppScreen _screen = AppScreen.location;
  GeoPoint? _userLocation;
  Space? _activeSpace;
  String? _anonymousName;
  String? _sessionId;
  Timer? _geofenceTimer;

  @override
  void initState() {
    super.initState();
    _checkSavedLocation();
  }

  @override
  void dispose() {
    _geofenceTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkSavedLocation() async {
    final saved = await LocationSelectionScreen.getSavedLocation();
    if (!mounted) return;
    if (saved != null) {
      setState(() {
        _userLocation = saved;
        _screen = AppScreen.discovery;
      });
    }
  }

  void _startGeofenceMonitoring() {
    _geofenceTimer?.cancel();
    _geofenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkGeofence(),
    );
  }

  Future<void> _checkGeofence() async {
    if (_activeSpace == null || _sessionId == null) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      final result = await widget.api.validateLocation(
        spaceId: _activeSpace!.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );

      if (!mounted) return;

      if (result.lifecycleState == 'outside' ||
          result.lifecycleState == 'expired') {
        _geofenceTimer?.cancel();
        _showExitDialog();
      }
    } catch (_) {}
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpaceColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          'Left Space Area',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'You have moved outside the Space geofence. You will be removed from this Space.',
          style: TextStyle(color: SpaceColors.secondary),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _onGeofenceExit();
            },
            style: FilledButton.styleFrom(
              backgroundColor: SpaceColors.accent,
              foregroundColor: SpaceColors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_screen) {
      AppScreen.location => LocationSelectionScreen(
          onLocationSelected: _onLocationSelected,
        ),
      AppScreen.discovery => SpaceDiscoveryScreen(
          api: widget.api,
          latitude: _userLocation!.latitude,
          longitude: _userLocation!.longitude,
          onJoinSpace: _onJoinSpace,
          onCreateSpace: _onCreateSpace,
          onChangeLocation: _onChangeLocation,
          onLogout: _onLogout,
        ),
      AppScreen.chat => _ChatScreen(
          space: _activeSpace!,
          sessionId: _sessionId!,
          anonymousName: _anonymousName!,
          api: widget.api,
          onExited: _onGeofenceExit,
          onLeave: _onLeaveSpace,
        ),
    };
  }

  void _onLocationSelected(GeoPoint point) {
    setState(() {
      _userLocation = point;
      _screen = AppScreen.discovery;
    });
  }

  Future<void> _onJoinSpace(Space space) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final session = await widget.api.joinSpace(
        space.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );

      setState(() {
        _activeSpace = space;
        _anonymousName = session.anonymousId;
        _sessionId = session.id;
        _screen = AppScreen.chat;
      });

      _startGeofenceMonitoring();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not join: ${e.toString()}'),
          backgroundColor: SpaceColors.card,
        ),
      );
    }
  }

  void _onCreateSpace() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CreateSpaceFlow(
          api: widget.api,
          userLocation: _userLocation!,
          onCreated: (space) {
            Navigator.of(context).pop();
            _onJoinSpace(space);
          },
        ),
      ),
    );
  }

  void _onChangeLocation() async {
    await LocationSelectionScreen.clearLocation();
    if (!mounted) return;
    setState(() => _screen = AppScreen.location);
  }

  void _onLogout() {
    setState(() {
      _activeSpace = null;
      _anonymousName = null;
      _sessionId = null;
      _screen = AppScreen.discovery;
    });
  }

  void _onGeofenceExit() {
    if (_activeSpace != null) {
      widget.api.leaveSpace(_activeSpace!.id);
    }
    setState(() {
      _activeSpace = null;
      _anonymousName = null;
      _sessionId = null;
      _screen = AppScreen.discovery;
    });
  }

  void _onLeaveSpace() {
    if (_activeSpace != null) {
      widget.api.leaveSpace(_activeSpace!.id);
    }
    _geofenceTimer?.cancel();
    setState(() {
      _activeSpace = null;
      _anonymousName = null;
      _sessionId = null;
      _screen = AppScreen.discovery;
    });
  }
}

class _CreateSpaceFlow extends StatelessWidget {
  const _CreateSpaceFlow({
    required this.api,
    required this.userLocation,
    required this.onCreated,
  });

  final ApiService api;
  final GeoPoint userLocation;
  final ValueChanged<Space> onCreated;

  @override
  Widget build(BuildContext context) {
    return CreateSpaceScreen(
      api: api,
      initialLocation: userLocation,
      onCreated: onCreated,
    );
  }
}

class CreateSpaceScreen extends StatefulWidget {
  const CreateSpaceScreen({
    super.key,
    required this.api,
    required this.initialLocation,
    required this.onCreated,
  });

  final ApiService api;
  final GeoPoint initialLocation;
  final ValueChanged<Space> onCreated;

  @override
  State<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends State<CreateSpaceScreen> {
  final _nameController = TextEditingController();
  final _validator = const GeofenceValidator();
  bool _isPrivate = false;
  double _radius = 120;
  late GeoPoint _selectedPoint;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialLocation;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
      accuracyMeters: 18,
      capturedAt: DateTime.now().toUtc(),
    );
    final validation = _validator.validate(
      geofence: geofence,
      current: currentFix,
    );

    return Scaffold(
      backgroundColor: SpaceColors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.2,
            colors: [Color(0xFF13211F), SpaceColors.black],
            stops: [0, 0.58],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Expanded(
                    child: Text(
                      'Create Space',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Set up a new Space for your area.',
                style: TextStyle(
                  color: SpaceColors.secondary,
                  fontSize: 15,
                ),
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
                title: 'Geofence',
                child: Column(
                  children: [
                    GeofenceDecisionPanel(validation: validation),
                    const SizedBox(height: 12),
                    Slider(
                      value: _radius,
                      min: CircleGeofence.minRadiusMeters.toDouble(),
                      max: CircleGeofence.maxRadiusMeters.toDouble(),
                      divisions: CircleGeofence.maxRadiusMeters -
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
                label: _creating ? 'Creating...' : 'Create Space',
                icon: Icons.check_rounded,
                loading: _creating,
                onPressed: _creating ? null : _createSpace,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createSpace() async {
    setState(() => _creating = true);
    try {
      final response = await widget.api.createSpace(
        name: _nameController.text.trim().isEmpty
            ? 'Untitled Space'
            : _nameController.text.trim(),
        visibility: _isPrivate ? 'private' : 'public',
        latitude: _selectedPoint.latitude,
        longitude: _selectedPoint.longitude,
        radiusMeters: _radius.round(),
      );

      if (!mounted) return;
      widget.onCreated(
        Space(
          id: response['id'] as String,
          name: response['name'] as String,
          visibility: response['visibility'] as String,
          latitude: (response['latitude'] as num).toDouble(),
          longitude: (response['longitude'] as num).toDouble(),
          radiusMeters: response['radius_meters'] as int,
          createdAt: DateTime.parse(response['created_at'] as String),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create: ${e.toString()}'),
          backgroundColor: SpaceColors.card,
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}

class _ChatScreen extends StatefulWidget {
  const _ChatScreen({
    required this.space,
    required this.sessionId,
    required this.anonymousName,
    required this.api,
    required this.onExited,
    required this.onLeave,
  });

  final Space space;
  final String sessionId;
  final String anonymousName;
  final ApiService api;
  final VoidCallback onExited;
  final VoidCallback onLeave;

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <ChatMessage>[];
  bool _loadingMessages = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await widget.api.getMessages(widget.space.id);
      if (!mounted) return;
      setState(() {
        _messages.addAll(msgs.map((m) => ChatMessage(
              name: m.anonymousId,
              text: m.content,
              color: SpaceColors.accent,
              reactions: 0,
            )));
        _loadingMessages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        name: widget.anonymousName,
        text: text,
        color: SpaceColors.accent,
        reactions: 0,
      ));
      _controller.clear();
    });

    try {
      await widget.api.sendMessage(
        widget.space.id,
        widget.sessionId,
        text,
      );
    } catch (_) {}
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
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: SpaceColors.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.space.name,
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
                              const Icon(Icons.person_outline_rounded,
                                  size: 14, color: SpaceColors.secondary),
                              const SizedBox(width: 6),
                              Text(
                                widget.anonymousName,
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
                    IconButton(
                      onPressed: widget.onLeave,
                      icon: const Icon(
                        Icons.exit_to_app_rounded,
                        color: SpaceColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 48,
                              color: SpaceColors.disabled,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No messages yet',
                              style: TextStyle(
                                color: SpaceColors.secondary,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Start the conversation',
                              style: TextStyle(
                                color: SpaceColors.disabled,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return MessageCard(message: _messages[index]);
                        },
                      ),
          ),
          ChatComposer(
            controller: _controller,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// API-backed discovery screen
class SpaceDiscoveryScreen extends StatefulWidget {
  const SpaceDiscoveryScreen({
    super.key,
    required this.api,
    required this.latitude,
    required this.longitude,
    required this.onJoinSpace,
    required this.onCreateSpace,
    required this.onChangeLocation,
    required this.onLogout,
  });

  final ApiService api;
  final double latitude;
  final double longitude;
  final ValueChanged<Space> onJoinSpace;
  final VoidCallback onCreateSpace;
  final VoidCallback onChangeLocation;
  final VoidCallback onLogout;

  @override
  State<SpaceDiscoveryScreen> createState() => _SpaceDiscoveryScreenState();
}

class _SpaceDiscoveryScreenState extends State<SpaceDiscoveryScreen> {
  List<SpaceData> _spaces = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spaces = await widget.api.discoverSpaces(
        widget.latitude,
        widget.longitude,
      );
      if (!mounted) return;
      setState(() {
        _spaces = spaces;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good evening',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Spaces near you',
                          style: TextStyle(
                            color: SpaceColors.secondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onChangeLocation,
                    icon: const Icon(Icons.edit_location_rounded,
                        color: SpaceColors.secondary),
                  ),
                  IconButton(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout_rounded,
                        color: SpaceColors.secondary),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: const TextStyle(
                                color: SpaceColors.secondary)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _discover,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_spaces.isEmpty)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.radar_rounded,
                            size: 48, color: SpaceColors.disabled),
                        const SizedBox(height: 16),
                        const Text(
                          'No Spaces nearby',
                          style: TextStyle(
                            color: SpaceColors.secondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Create one or move to a different location',
                          style: TextStyle(
                            color: SpaceColors.disabled,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _SpaceButton(
                          label: 'Create a Space',
                          icon: Icons.add_rounded,
                          onPressed: widget.onCreateSpace,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: _spaces.length,
                  itemBuilder: (context, index) {
                    final space = _spaces[index];
                    return _SpaceCard(
                      name: space.name,
                      distance: space.distanceMeters,
                      memberCount: space.memberCount,
                      joined: space.joined,
                      onTap: space.joined
                          ? () => widget.onJoinSpace(Space(
                                id: space.id,
                                name: space.name,
                                visibility: space.visibility,
                                latitude: space.latitude,
                                longitude: space.longitude,
                                radiusMeters: space.radiusMeters,
                                createdAt: DateTime.now(),
                              ))
                          : null,
                    );
                  },
                ),
              ),
            if (!_loading && _spaces.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _SpaceButton(
                  label: 'Create a Space',
                  icon: Icons.add_rounded,
                  onPressed: widget.onCreateSpace,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Reusable widgets
class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

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
        textStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19)),
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.name,
    required this.distance,
    this.memberCount = 0,
    this.joined = false,
    this.onTap,
  });

  final String name;
  final double distance;
  final int memberCount;
  final bool joined;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: joined
                ? SpaceColors.accent.withValues(alpha: 0.08)
                : SpaceColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: joined
                  ? SpaceColors.accent.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: joined
                      ? SpaceColors.accent.withValues(alpha: 0.15)
                      : SpaceColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  joined ? Icons.forum_rounded : Icons.radar_rounded,
                  color: joined ? SpaceColors.accent : SpaceColors.disabled,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.near_me_rounded,
                            size: 12, color: SpaceColors.secondary),
                        const SizedBox(width: 4),
                        Text(
                          '${distance.toStringAsFixed(0)}m',
                          style: const TextStyle(
                            color: SpaceColors.secondary,
                            fontSize: 12,
                          ),
                        ),
                        if (memberCount > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.people_outline_rounded,
                              size: 12, color: SpaceColors.secondary),
                          const SizedBox(width: 4),
                          Text(
                            '$memberCount',
                            style: const TextStyle(
                              color: SpaceColors.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (joined)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SpaceColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Joined',
                    style: TextStyle(
                      color: SpaceColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded,
                    color: SpaceColors.disabled),
            ],
          ),
        ),
      ),
    );
  }
}

// Keep existing shared widgets below
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
                    hintText: 'Message...',
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
            style:
                const TextStyle(color: SpaceColors.disabled, fontSize: 12),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
              color:
                  selected ? SpaceColors.accent : SpaceColors.disabled,
              hollow: !selected,
            ),
            const SizedBox(width: 9),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class GeofenceDecisionPanel extends StatelessWidget {
  const GeofenceDecisionPanel(
      {super.key, required this.validation});

  final GeofenceValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final color = switch (validation.decision) {
      GeofenceDecision.inside => SpaceColors.accent,
      GeofenceDecision.nearBoundary => const Color(0xFFF4C35C),
      GeofenceDecision.outside => const Color(0xFFFF6262),
      GeofenceDecision.lowAccuracy => const Color(0xFFF4C35C),
      GeofenceDecision.rejected => const Color(0xFFFF6262),
    };
    final label = switch (validation.decision) {
      GeofenceDecision.inside => 'Inside',
      GeofenceDecision.nearBoundary => 'Near boundary',
      GeofenceDecision.outside => 'Outside',
      GeofenceDecision.lowAccuracy => 'Low accuracy',
      GeofenceDecision.rejected => 'Rejected',
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
            child:
                Icon(Icons.radar_rounded, color: color, size: 20),
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
                  '${validation.distanceMeters.toStringAsFixed(1)}m from center',
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

class SpaceButton extends StatelessWidget {
  const SpaceButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 19),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: SpaceColors.accent,
        foregroundColor: SpaceColors.black,
        textStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19)),
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

class StatusDot extends StatelessWidget {
  const StatusDot(
      {super.key, required this.color, this.hollow = false});

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

class Space {
  Space({
    required this.id,
    required this.name,
    required this.visibility,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String visibility;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final DateTime createdAt;
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

class SpaceColors {
  static const black = Color(0xFF0B0B0C);
  static const surface = Color(0xFF151518);
  static const card = Color(0xFF1C1C20);
  static const white = Color(0xFFFFFFFF);
  static const secondary = Color(0xFFB4B4BC);
  static const disabled = Color(0xFF6E6E78);
  static const accent = Color(0xFF37D399);
}

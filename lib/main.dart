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
import 'package:space_mobile/services/chat_socket.dart';

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

enum AppScreen { location, discovery, chat, mySpaces }

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
      AppScreen.discovery || AppScreen.mySpaces => _buildHomeTabs(),
      AppScreen.chat => ChatScreen(
          space: _activeSpace!,
          sessionId: _sessionId!,
          anonymousName: _anonymousName!,
          api: widget.api,
          onExited: _onGeofenceExit,
          onLeave: _onLeaveSpace,
        ),
    };
  }

  Widget _buildHomeTabs() {
    final selectedIndex = _screen == AppScreen.discovery ? 0 : 1;
    return Scaffold(
      backgroundColor: SpaceColors.black,
      body: _screen == AppScreen.discovery
          ? SpaceDiscoveryScreen(
              api: widget.api,
              latitude: _userLocation!.latitude,
              longitude: _userLocation!.longitude,
              onJoinSpace: _onJoinSpace,
              onCreateSpace: _onCreateSpace,
              onChangeLocation: _onChangeLocation,
              onLogout: _onLogout,
            )
          : MySpacesScreen(
              api: widget.api,
              onOpenSpace: _onJoinSpace,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _screen = index == 0 ? AppScreen.discovery : AppScreen.mySpaces;
          });
        },
        backgroundColor: const Color(0xFF0F0F12),
        indicatorColor: SpaceColors.accent.withValues(alpha: 0.18),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar_rounded, color: SpaceColors.disabled),
            selectedIcon: Icon(Icons.radar_rounded, color: SpaceColors.accent),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_rounded, color: SpaceColors.disabled),
            selectedIcon: Icon(Icons.forum_rounded, color: SpaceColors.accent),
            label: 'My Spaces',
          ),
        ],
      ),
    );
  }

  void _onLocationSelected(GeoPoint point) {
    setState(() {
      _userLocation = point;
      _screen = AppScreen.discovery;
    });
  }

  Future<bool> _onJoinSpace(Space space) async {
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
      return true;
    } catch (e) {
      if (mounted) {
        final message = e is ApiException && e.statusCode == 403
            ? 'You need to be inside the space area to join it'
            : 'Could not join: ${e.toString()}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: SpaceColors.card,
          ),
        );
      }
      return false;
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

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.space,
    required this.sessionId,
    required this.anonymousName,
    required this.api,
    required this.onExited,
    required this.onLeave,
    this.socket,
  });

  final Space space;
  final String sessionId;
  final String anonymousName;
  final ApiService api;
  final VoidCallback onExited;
  final VoidCallback onLeave;
  final ChatSocket? socket;

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <ChatMessage>[];
  final _messageIds = <String>{};
  bool _loadingMessages = true;
  ChatMessage? _replyingTo;
  late final ChatSocket _socket;

  @override
  void initState() {
    super.initState();
    _socket = widget.socket ??
        ChatSocket(
          baseUrl: widget.api.client.baseUrl,
          getAccessToken: () => widget.api.client.accessToken ?? '',
          spaceId: widget.space.id,
        );
    _socket.events.listen(_onWsEvent, onError: (_) {});
    _loadMessages();
    _socket.connect();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.socket == null) _socket.dispose();
    super.dispose();
  }

  void _onWsEvent(WsEvent event) {
    switch (event) {
      case WsMessageEvent(:final message):
        _onIncomingMessage(message);
      case WsReactionEvent(:final messageId, :final emoji, :final count):
        _onReaction(messageId, emoji, count);
    }
  }

  void _onIncomingMessage(MessageData message) {
    if (!mounted || _messageIds.contains(message.id)) return;
    _messageIds.add(message.id);
    setState(() {
      _messages.add(ChatMessage(
        id: message.id,
        name: message.anonymousId,
        text: message.content,
        replyTo: message.replyTo,
        replyText: message.replyContent,
        color: SpaceColors.accent,
        reactions: message.reactions.fold<Map<String, int>>(
          {},
          (map, r) => map..[r.emoji] = r.count,
        ),
      ));
    });
  }

  void _onReaction(String messageId, String emoji, int count) {
    if (!mounted) return;
    for (final message in _messages) {
      if (message.id == messageId) {
        setState(() => message.reactions[emoji] = count);
        return;
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await widget.api.getMessages(widget.space.id);
      if (!mounted) return;
      setState(() {
        for (final m in msgs) {
          if (_messageIds.add(m.id)) {
            _messages.add(ChatMessage(
              id: m.id,
              name: m.anonymousId,
              text: m.content,
              replyTo: m.replyTo,
              replyText: m.replyContent,
              color: SpaceColors.accent,
              reactions: m.reactions.fold<Map<String, int>>(
                {},
                (map, r) => map..[r.emoji] = r.count,
              ),
            ));
          }
        }
        _loadingMessages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final replyTo = _replyingTo;
    _controller.clear();
    setState(() => _replyingTo = null);

    try {
      final saved = await widget.api.sendMessage(
        widget.space.id,
        widget.sessionId,
        text,
        replyTo: replyTo?.id,
      );
      _onIncomingMessage(saved);
    } catch (_) {
      if (mounted && replyTo != null) setState(() => _replyingTo = replyTo);
    }
  }

  void _startReply(ChatMessage message) {
    setState(() => _replyingTo = message);
  }

  Future<void> _addReaction(ChatMessage message, String emoji) async {
    try {
      await widget.api.reactToMessage(message.id, widget.sessionId, emoji);
    } catch (_) {}
  }

  void _showMessageActions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpaceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SpaceColors.secondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final emoji in _reactionEmojis)
                      _ReactionButton(
                        emoji: emoji,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _addReaction(message, emoji);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.reply_rounded,
                      color: SpaceColors.secondary),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startReply(message);
                  },
                ),
                if (message.name == widget.anonymousName)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFE57373)),
                    title: const Text('Delete',
                        style: TextStyle(color: Color(0xFFE57373))),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmDelete(message);
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined,
                      color: SpaceColors.secondary),
                  title: const Text('Report'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showReportOptions(message);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SpaceColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('Delete message?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
          'This removes the message for everyone. Available within 15 minutes of sending.',
          style: TextStyle(color: SpaceColors.secondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
              foregroundColor: SpaceColors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.api.deleteMessage(message.id);
      if (!mounted) return;
      setState(() {
        _messages.remove(message);
        _messageIds.remove(message.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted'),
          backgroundColor: SpaceColors.card,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final messageText = e.statusCode == 403
          ? 'Only your own messages can be deleted'
          : 'Could not delete message';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageText), backgroundColor: SpaceColors.card),
      );
    }
  }

  void _showReportOptions(ChatMessage message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: SpaceColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('Report message',
            style: TextStyle(fontWeight: FontWeight.w700)),
        children: [
          for (final reason in _reportReasons)
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _sendReport(message, reason);
              },
              child: Text(reason),
            ),
        ],
      ),
    );
  }

  Future<void> _sendReport(ChatMessage message, String reason) async {
    try {
      await widget.api.reportMessage(message.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks, report submitted'),
          backgroundColor: SpaceColors.card,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not submit report'),
          backgroundColor: SpaceColors.card,
        ),
      );
    }
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
                          final message = _messages[index];
                          return MessageCard(
                            message: message,
                            onLongPress: () => _showMessageActions(message),
                          );
                        },
                      ),
          ),
          ChatComposer(
            controller: _controller,
            onSend: _sendMessage,
            replyingTo: _replyingTo,
            onCancelReply: () => setState(() => _replyingTo = null),
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
  final Future<bool> Function(Space) onJoinSpace;
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
  String? _joiningId;

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

  Space _toSpace(SpaceData data) => Space(
        id: data.id,
        name: data.name,
        visibility: data.visibility,
        latitude: data.latitude,
        longitude: data.longitude,
        radiusMeters: data.radiusMeters,
        createdAt: DateTime.now(),
      );

  Future<void> _join(SpaceData data) async {
    if (_joiningId != null) return;
    setState(() => _joiningId = data.id);
    final ok = await widget.onJoinSpace(_toSpace(data));
    if (mounted) setState(() => _joiningId = null);
    if (ok && mounted) _discover();
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
                      loading: _joiningId == space.id,
                      onTap: _joiningId == null
                          ? () => _join(space)
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

// API-backed My Spaces screen
class MySpacesScreen extends StatefulWidget {
  const MySpacesScreen({
    super.key,
    required this.api,
    required this.onOpenSpace,
  });

  final ApiService api;
  final Future<bool> Function(Space) onOpenSpace;

  @override
  State<MySpacesScreen> createState() => _MySpacesScreenState();
}

class _MySpacesScreenState extends State<MySpacesScreen> {
  List<SpaceData> _spaces = [];
  bool _loading = true;
  String? _error;
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spaces = await widget.api.joinedSpaces();
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

  Space _toSpace(SpaceData data) => Space(
        id: data.id,
        name: data.name,
        visibility: data.visibility,
        latitude: data.latitude,
        longitude: data.longitude,
        radiusMeters: data.radiusMeters,
        createdAt: DateTime.now(),
      );

  Future<void> _open(SpaceData data) async {
    if (_openingId != null) return;
    setState(() => _openingId = data.id);
    final ok = await widget.onOpenSpace(_toSpace(data));
    if (mounted) setState(() => _openingId = null);
    if (ok && mounted) _load();
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
                          'My Spaces',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Spaces you are in',
                          style: TextStyle(
                            color: SpaceColors.secondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded,
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
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_spaces.isEmpty)
              const Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 48, color: SpaceColors.disabled),
                        SizedBox(height: 16),
                        Text(
                          'You are not in any Spaces',
                          style: TextStyle(
                            color: SpaceColors.secondary,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Join one from the Discover tab',
                          style: TextStyle(
                            color: SpaceColors.disabled,
                            fontSize: 13,
                          ),
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
                      memberCount: space.memberCount,
                      joined: true,
                      loading: _openingId == space.id,
                      onTap: _openingId == null
                          ? () => _open(space)
                          : null,
                    );
                  },
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
    this.distance = 0,
    this.memberCount = 0,
    this.joined = false,
    this.loading = false,
    this.onTap,
  });

  final String name;
  final double distance;
  final int memberCount;
  final bool joined;
  final bool loading;
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
                        if (distance > 0) ...[
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
                        ],
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
              else if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SpaceColors.accent,
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
    this.replyingTo,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ChatMessage? replyingTo;
  final VoidCallback? onCancelReply;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyingTo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: SpaceColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.reply_rounded,
                          size: 14, color: SpaceColors.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Replying to ${replyingTo!.name}: '
                          '${replyingTo!.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SpaceColors.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (onCancelReply != null)
                        GestureDetector(
                          onTap: onCancelReply,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: SpaceColors.disabled,
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
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
            ],
          ),
        ),
      ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard({
    super.key,
    required this.message,
    this.onLongPress,
  });

  final ChatMessage message;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
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
            if (message.replyText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: SpaceColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        size: 13, color: SpaceColors.secondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${message.replyText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpaceColors.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              message.text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.35,
                color: SpaceColors.white,
              ),
            ),
            if (message.reactions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in message.reactions.entries)
                    if (entry.value > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: SpaceColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value}',
                          style: const TextStyle(
                            color: SpaceColors.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 14),
          ],
        ),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.2,
            colors: [Color(0xFF13211F), SpaceColors.black],
            stops: [0, 0.58],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: child,
        ),
      ),
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
    required this.id,
    required this.name,
    required this.text,
    required this.color,
    required this.reactions,
    this.replyTo,
    this.replyText,
  });

  final String id;
  final String name;
  final String text;
  final Color color;
  final String? replyTo;
  final String? replyText;
  final Map<String, int> reactions;
}

const _reactionEmojis = ['👍', '❤️', '😄', '😂', '🔥', '🎉'];

const _reportReasons = [
  'Spam',
  'Harassment',
  'Hate speech',
  'Inappropriate content',
  'Other',
];

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SpaceColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
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

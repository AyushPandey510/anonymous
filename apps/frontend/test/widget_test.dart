import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:space_mobile/main.dart';
import 'package:space_mobile/services/api_client.dart';
import 'package:space_mobile/services/api_service.dart';
import 'package:space_mobile/services/chat_socket.dart';
import 'package:space_mobile/theme.dart';

class _FakeChatSocket extends ChatSocket {
  _FakeChatSocket(this._incoming)
    : super(
        baseUrl: 'http://test',
        getAccessToken: () => 'token',
        spaceId: 'space-1',
      );

  final StreamController<WsEvent> _incoming;
  bool connected = false;

  @override
  Stream<WsEvent> get events => _incoming.stream;

  @override
  void connect() => connected = true;

  @override
  void dispose() {}
}

void main() {
  testWidgets('renders Space loading state', (tester) async {
    await tester.pumpWidget(const SpaceApp());

    expect(find.byType(SpaceApp), findsOneWidget);
    expect(find.text('Finding your orbit...'), findsOneWidget);
  });

  testWidgets('discovery renders space cards and joins a public space', (
    tester,
  ) async {
    var joinCalled = false;
    final mock = MockClient((request) async {
      if (request.url.path.contains('/spaces/discover')) {
        return http.Response(
          jsonEncode([
            {
              'id': 'space-1',
              'name': 'Test Space',
              'visibility': 'public',
              'latitude': 12.97,
              'longitude': 77.59,
              'radius_meters': 100,
              'distance_meters': 50,
              'member_count': 3,
              'joined': false,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/join')) {
        joinCalled = true;
        return http.Response(
          jsonEncode({
            'id': 'session-1',
            'space_id': 'space-1',
            'anonymous_id': 'anon-1',
            'expires_at': '2026-01-02T00:00:00Z',
            'status': 'active',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    var joinedSpaceId = '';
    await tester.pumpWidget(
      MaterialApp(
        home: SpaceDiscoveryScreen(
          api: api,
          latitude: 12.97,
          longitude: 77.59,
          onJoinSpace: (space) async {
            joinedSpaceId = space.id;
            await api.joinSpace(space.id, latitude: 12.97, longitude: 77.59);
            return true;
          },
          onJoinInvite: (_) async => true,
          onCreateSpace: () {},
          onChangeLocation: () {},
          onLogout: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Test Space'), findsOneWidget);
    expect(find.text('Joined'), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);

    await tester.tap(find.text('Test Space'));
    await tester.pump();
    await tester.pump();

    expect(joinCalled, isTrue);
    expect(joinedSpaceId, 'space-1');
  });

  testWidgets('discovery card fits on narrow Android viewport', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1.875;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final mock = MockClient((request) async {
      if (request.url.path.contains('/spaces/discover')) {
        return http.Response(
          jsonEncode([
            {
              'id': 'space-1',
              'name': 'A Very Calm Neighborhood Space',
              'description':
                  'A nearby place for thoughtful local conversations.',
              'visibility': 'public',
              'latitude': 12.97,
              'longitude': 77.59,
              'radius_meters': 100,
              'distance_meters': 50,
              'member_count': 3,
              'joined': false,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildSpaceTheme(Brightness.light),
        darkTheme: buildSpaceTheme(Brightness.dark),
        home: SpaceDiscoveryScreen(
          api: api,
          latitude: 12.97,
          longitude: 77.59,
          onJoinSpace: (_) async => true,
          onJoinInvite: (_) async => true,
          onCreateSpace: () {},
          onChangeLocation: () {},
          onLogout: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('A Very Calm Neighborhood Space'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat renders websocket messages and sends via POST', (
    tester,
  ) async {
    final incoming = StreamController<WsEvent>.broadcast();
    final socket = _FakeChatSocket(incoming);

    var sentContent = '';
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/messages')) {
        if (request.method == 'GET') {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        sentContent = jsonDecode(request.body)['content'] as String;
        return http.Response(
          jsonEncode({
            'id': 'm2',
            'space_id': 'space-1',
            'anonymous_id': 'anon-me',
            'content': sentContent,
            'created_at': '2026-01-01T00:00:01Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          space: Space(
            id: 'space-1',
            name: 'Test Space',
            visibility: 'public',
            latitude: 12.97,
            longitude: 77.59,
            radiusMeters: 100,
            createdAt: DateTime.utc(2026),
          ),
          sessionId: 'session-1',
          anonymousName: 'anon-me',
          api: api,
          onExited: () {},
          onLeave: () {},
          socket: socket,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(socket.connected, isTrue);

    incoming.add(
      WsMessageEvent(
        MessageData(
          id: 'm1',
          anonymousId: 'anon-2',
          content: 'hello from websocket',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('hello from websocket'), findsOneWidget);

    incoming.add(
      WsMessageEvent(
        MessageData(
          id: 'm1',
          anonymousId: 'anon-2',
          content: 'hello from websocket',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('hello from websocket'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sent via post');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();

    expect(sentContent, 'sent via post');
    expect(find.text('sent via post'), findsOneWidget);

    await incoming.close();
  });

  testWidgets('long-press sends a reaction and reaction event updates chip', (
    tester,
  ) async {
    final incoming = StreamController<WsEvent>.broadcast();
    final socket = _FakeChatSocket(incoming);

    String? reactedEmoji;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/messages')) {
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/react')) {
        reactedEmoji = jsonDecode(request.body)['emoji'] as String;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          space: Space(
            id: 'space-1',
            name: 'Test Space',
            visibility: 'public',
            latitude: 12.97,
            longitude: 77.59,
            radiusMeters: 100,
            createdAt: DateTime.utc(2026),
          ),
          sessionId: 'session-1',
          anonymousName: 'anon-me',
          api: api,
          onExited: () {},
          onLeave: () {},
          socket: socket,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    incoming.add(
      WsMessageEvent(
        MessageData(
          id: 'm1',
          anonymousId: 'anon-2',
          content: 'react to me',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('react to me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    expect(reactedEmoji, '👍');

    incoming.add(const WsReactionEvent(messageId: 'm1', emoji: '👍', count: 2));
    await tester.pump();
    await tester.pump();

    expect(find.text('👍 2'), findsOneWidget);

    await incoming.close();
  });

  testWidgets('replying sends message with reply_to and restores on failure', (
    tester,
  ) async {
    final incoming = StreamController<WsEvent>.broadcast();
    final socket = _FakeChatSocket(incoming);

    String? replyTo;
    var failNext = false;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/messages')) {
        if (request.method == 'GET') {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        replyTo = body['reply_to'] as String?;
        if (failNext) {
          failNext = false;
          return http.Response('error', 500);
        }
        return http.Response(
          jsonEncode({
            'id': 'm2',
            'space_id': 'space-1',
            'anonymous_id': 'anon-me',
            'content': body['content'],
            'reply_to': body['reply_to'],
            'created_at': '2026-01-01T00:00:01Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          space: Space(
            id: 'space-1',
            name: 'Test Space',
            visibility: 'public',
            latitude: 12.97,
            longitude: 77.59,
            radiusMeters: 100,
            createdAt: DateTime.utc(2026),
          ),
          sessionId: 'session-1',
          anonymousName: 'anon-me',
          api: api,
          onExited: () {},
          onLeave: () {},
          socket: socket,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    incoming.add(
      WsMessageEvent(
        MessageData(
          id: 'm1',
          anonymousId: 'anon-2',
          content: 'original message',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('original message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Replying to anon-2'), findsOneWidget);

    failNext = true;
    await tester.enterText(find.byType(TextField), 'my reply');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(replyTo, 'm1');
    expect(find.textContaining('Replying to anon-2'), findsOneWidget);

    await incoming.close();
  });

  testWidgets('My Spaces lists joined spaces and opens them on tap', (
    tester,
  ) async {
    var openCalled = false;
    String? openedId;
    final mock = MockClient((request) async {
      if (request.url.path == '/me/joined-spaces') {
        return http.Response(
          jsonEncode([
            {
              'id': 'space-1',
              'name': 'Parivartan',
              'visibility': 'public',
              'latitude': 12.97,
              'longitude': 77.59,
              'radius_meters': 100,
              'created_at': '2026-01-01T00:00:00Z',
            },
            {
              'id': 'space-2',
              'name': 'MySpace',
              'visibility': 'public',
              'latitude': 12.97,
              'longitude': 77.59,
              'radius_meters': 100,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        home: MySpacesScreen(
          api: api,
          onOpenSpace: (space) async {
            openCalled = true;
            openedId = space.id;
            return true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Parivartan'), findsOneWidget);
    expect(find.text('MySpace'), findsOneWidget);

    await tester.tap(find.text('Parivartan'));
    await tester.pump();
    await tester.pump();

    expect(openCalled, isTrue);
    expect(openedId, 'space-1');
  });

  testWidgets('My Spaces shows empty state when no joined spaces', (
    tester,
  ) async {
    final mock = MockClient((request) async {
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        home: MySpacesScreen(api: api, onOpenSpace: (_) async => true),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('You are not in any Spaces'), findsOneWidget);
  });

  testWidgets('Delete own message via long-press flow', (tester) async {
    final incoming = StreamController<WsEvent>.broadcast();
    var deleteCalled = false;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/messages')) {
        if (request.method == 'GET') {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'm9',
            'space_id': 'space-1',
            'anonymous_id': 'anon-me',
            'content': 'x',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/messages/m1/delete') {
        deleteCalled = true;
        return http.Response(
          jsonEncode({'status': 'deleted'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          space: Space(
            id: 'space-1',
            name: 'Test Space',
            visibility: 'public',
            latitude: 12.97,
            longitude: 77.59,
            radiusMeters: 100,
            createdAt: DateTime.utc(2026),
          ),
          sessionId: 'session-1',
          anonymousName: 'anon-me',
          api: api,
          onExited: () {},
          onLeave: () {},
          socket: _FakeChatSocket(incoming),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    incoming.add(
      WsMessageEvent(
        MessageData(
          id: 'm1',
          anonymousId: 'anon-me',
          content: 'my own message',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('my own message'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete message?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isTrue);
    expect(find.text('my own message'), findsNothing);
    expect(find.text('Message deleted'), findsOneWidget);
    await incoming.close();
  });

  testWidgets('Report a message via long-press flow', (tester) async {
    final incoming = StreamController<WsEvent>.broadcast();
    String? reportedReason;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/messages')) {
        if (request.method == 'GET') {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'm9',
            'space_id': 'space-1',
            'anonymous_id': 'anon-me',
            'content': 'x',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/messages/m1/report') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        reportedReason = body['reason'] as String?;
        return http.Response(
          jsonEncode({'id': 'r1', 'status': 'pending'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiService(ApiClient('http://test', client: mock));

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          space: Space(
            id: 'space-1',
            name: 'Test Space',
            visibility: 'public',
            latitude: 12.97,
            longitude: 77.59,
            radiusMeters: 100,
            createdAt: DateTime.utc(2026),
          ),
          sessionId: 'session-1',
          anonymousName: 'anon-me',
          api: api,
          onExited: () {},
          onLeave: () {},
          socket: _FakeChatSocket(incoming),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    incoming.add(
      WsMessageEvent(
        MessageData(
          id: 'm1',
          anonymousId: 'anon-2',
          content: 'offensive message',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('offensive message'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report message'), findsOneWidget);

    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();

    expect(reportedReason, 'Spam');
    expect(find.text('Thanks, report submitted'), findsOneWidget);
    await incoming.close();
  });
}

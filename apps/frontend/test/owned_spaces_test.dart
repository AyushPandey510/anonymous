import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:space_mobile/main.dart';
import 'package:space_mobile/services/api_client.dart';
import 'package:space_mobile/services/api_service.dart';

void main() {
  for (final mode in ['owner', 'owner_joined', 'member']) {
    final active = mode != 'owner';
    final owner = mode != 'member';
    testWidgets('private space invites are accessible: $mode', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final space = {
        'id': 'owned',
        'name': 'Private Space',
        'visibility': 'private',
        'latitude': 12.97,
        'longitude': 77.59,
        'radius_meters': 100,
        'created_at': '2026-01-01T00:00:00Z',
      };
      var opened = false;
      final publicSpace = {
        ...space,
        'id': 'public',
        'name': 'Public Space',
        'visibility': 'public',
      };
      var invited = false;
      final api = ApiService(
        ApiClient(
          'http://test',
          client: MockClient((request) async {
            if (request.url.path == '/me/spaces') {
              return http.Response(
                jsonEncode([
                  if (owner) space,
                  publicSpace,
                  {
                    ...publicSpace,
                    'id': 'left-public',
                    'name': 'Left Public Space',
                  },
                ]),
                200,
              );
            }
            if (request.url.path == '/me/joined-spaces') {
              return http.Response(
                jsonEncode([if (active) space, publicSpace]),
                200,
              );
            }
            if (request.url.path == '/spaces/owned/invitations') {
              invited = true;
              return http.Response('{"invite_code":"TEST1234"}', 200);
            }
            return http.Response('{}', 404);
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MySpacesScreen(
            api: api,
            onOpenSpace: (_) async {
              opened = true;
              return false;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Private Space'), findsOneWidget);
      expect(find.text('Owner'), owner ? findsOneWidget : findsNothing);
      expect(find.text('Public Space'), findsOneWidget);
      expect(find.text('Left Public Space'), findsNothing);
      expect(find.byTooltip('Invite Code'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Invite Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(invited, isTrue);
      expect(find.text('TEST1234'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Enter Space').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(opened, isTrue);
    });
  }
}

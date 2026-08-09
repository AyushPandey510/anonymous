import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:space_mobile/services/api_client.dart';

void main() {
  test('getList refreshes an expired access token and retries', () async {
    var refreshCalls = 0;
    var listCalls = 0;
    final client = ApiClient(
      'http://test',
      client: MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          return http.Response(
            jsonEncode({
              'access_token': 'new-access',
              'refresh_token': 'new-refresh',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/spaces/discover') {
          listCalls++;
          if (listCalls == 1) {
            expect(request.headers['Authorization'], 'Bearer old-access');
            return http.Response(
              jsonEncode({'error': 'Unauthorized'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response(
            jsonEncode([{'id': 'space-1'}]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );
    client.accessToken = 'old-access';
    client.refreshToken = 'refresh-token';

    final result = await client.getList('/spaces/discover');

    expect(refreshCalls, 1);
    expect(listCalls, 2);
    expect(client.accessToken, 'new-access');
    expect(client.refreshToken, 'new-refresh');
    expect(result, hasLength(1));
  });

  test('getList throws 401 when refresh token is also rejected', () async {
    final client = ApiClient(
      'http://test',
      client: MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          return http.Response(
            jsonEncode({'error': 'Unauthorized'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'error': 'Unauthorized'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    client.accessToken = 'old-access';
    client.refreshToken = 'revoked-refresh';

    expect(
      () => client.getList('/spaces/discover'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
  });
}

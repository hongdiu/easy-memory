import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:easy_memory/models/remote_endpoint.dart';
import 'package:easy_memory/services/remote_delete_service.dart';

void main() {
  late HttpServer server;
  late int port;
  late RemoteDeleteService service;
  String? receivedApiKey;
  String? receivedPath;

  setUp(() async {
    service = RemoteDeleteService();
    receivedApiKey = null;
    receivedPath = null;

    Future<shelf.Response> handler(shelf.Request request) async {
      if (request.url.path == 'api/delete') {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        receivedPath = data['path'] as String?;
        receivedApiKey = request.headers['x-api-key'];

        if (request.headers['x-api-key'] == 'wrong-key') {
          return shelf.Response.unauthorized(
            jsonEncode({'success': false, 'error': '未授权'}),
          );
        }
        return shelf.Response.ok(jsonEncode({'success': true}));
      }
      return shelf.Response.notFound('Not Found');
    }

    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    port = server.port;
  });

  tearDown(() async {
    await server.close(force: true);
  });

  group('RemoteDeleteService.deleteFile', () {
    test('sends delete request with path and returns success', () async {
      final endpoint = RemoteEndpoint(id: '1', label: '测试', host: '127.0.0.1', port: port);
      final result = await service.deleteFile(endpoint: endpoint, filePath: '/tmp/test.pdf');

      expect(result.success, isTrue);
      expect(receivedPath, '/tmp/test.pdf');
    });

    test('sends X-Api-Key header when endpoint has apiKey', () async {
      final endpoint = RemoteEndpoint(id: '1', label: '测试', host: '127.0.0.1', port: port, apiKey: 'secret');
      final result = await service.deleteFile(endpoint: endpoint, filePath: '/tmp/test.pdf');

      expect(result.success, isTrue);
      expect(receivedApiKey, 'secret');
    });

    test('does not send X-Api-Key header when endpoint has empty apiKey', () async {
      final endpoint = RemoteEndpoint(id: '1', label: '测试', host: '127.0.0.1', port: port);
      await service.deleteFile(endpoint: endpoint, filePath: '/tmp/test.pdf');

      expect(receivedApiKey, isNull);
    });

    test('returns failure when server rejects (401)', () async {
      final endpoint = RemoteEndpoint(id: '1', label: '测试', host: '127.0.0.1', port: port, apiKey: 'wrong-key');
      final result = await service.deleteFile(endpoint: endpoint, filePath: '/tmp/test.pdf');

      expect(result.success, isFalse);
      expect(result.statusCode, 401);
      expect(result.message, contains('未授权'));
    });

    test('returns failure on connection error', () async {
      // Use a port that is not listening
      final endpoint = RemoteEndpoint(id: '1', label: '测试', host: '127.0.0.1', port: 1);
      final result = await service.deleteFile(endpoint: endpoint, filePath: '/tmp/test.pdf');

      expect(result.success, isFalse);
      expect(result.message, contains('无法连接'));
    });
  });
}
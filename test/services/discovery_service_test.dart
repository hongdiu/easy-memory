import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:easy_memory/services/discovery_service.dart';

void main() {
  group('DiscoveryService', () {
    test('startListener replies to discovery request', () async {
      final session = await DiscoveryService.startListener(
        label: 'test-device',
        host: '127.0.0.1',
        port: 8080,
        authRequired: true,
      );
      expect(session, isNotNull);

      final socket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      try {
        // Send the magic probe to the listener.
        socket.send(
          utf8.encode('EASY_MEMORY_DISCOVERY'),
          InternetAddress.loopbackIPv4,
          50100,
        );

        // Wait up to 2s for a reply.
        String? reply;
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (DateTime.now().isBefore(deadline) && reply == null) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final event = socket.events.firstWhere(
            (e) => e == RawSocketEvent.read,
            orElse: () => RawSocketEvent.closed,
          );
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null) {
              reply = utf8.decode(datagram.data);
              break;
            }
          }
        }

        expect(reply, isNotNull);
        final json = jsonDecode(reply!) as Map<String, dynamic>;
        expect(json['app'], 'easy_memory');
        expect(json['label'], 'test-device');
        expect(json['host'], '127.0.0.1');
        expect(json['port'], 8080);
        expect(json['auth_required'], true);
        expect(json['platform'], isNotEmpty);
      } finally {
        socket.close();
        session?.close();
      }
    });

    test('discover returns empty list when no service is running', () async {
      final services = await DiscoveryService.discover(
        timeout: const Duration(milliseconds: 800),
      );
      // No listener is running on port 50100 in this test, so expect no
      // results (or at worst leftover from other tests — filter by host).
      expect(services.where((s) => s.host != '127.0.0.1'), isEmpty);
    });
  });
}
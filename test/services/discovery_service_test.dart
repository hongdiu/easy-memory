import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:easy_memory/services/discovery_service.dart';

void main() {
  // Use an isolated discovery port so this suite never collides with the
  // web_server_service_test listener (also bound to 50100) when CI runs
  // test files in parallel — otherwise SO_REUSEADDR may deliver our probe
  // to the wrong listener and we'd assert against another test's label.
  const int testUdpPort = 50101;

  group('DiscoveryService', () {
    test('startListener replies to discovery request', () async {
      final session = await DiscoveryService.startListener(
        label: 'test-device',
        host: '127.0.0.1',
        port: 8080,
        authRequired: true,
        udpPort: testUdpPort,
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
          testUdpPort,
        );

        // Wait up to 2s for a reply.
        String? reply;
        final replyCompleter = Completer<String?>();
        final sub = socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram != null && !replyCompleter.isCompleted) {
            replyCompleter.complete(utf8.decode(datagram.data));
          }
        });
        final timer = Timer(const Duration(seconds: 2), () {
          if (!replyCompleter.isCompleted) replyCompleter.complete(null);
        });
        try {
          reply = await replyCompleter.future;
        } finally {
          timer.cancel();
          await sub.cancel();
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
      // Use an isolated port that nothing listens on. In CI, other test files
      // may run in parallel and start a discovery listener on port 50100,
      // whose broadcast reply would otherwise pollute this assertion.
      final services = await DiscoveryService.discover(
        timeout: const Duration(milliseconds: 800),
        targetPort: 50199,
      );
      expect(services, isEmpty);
    });
  });

  group('DiscoveryService._resolveReplyAddress', () {
    test('keeps a normal unicast sender address', () {
      expect(
        DiscoveryService.resolveReplyAddress(
          InternetAddress('192.168.1.50'),
        ).address,
        '192.168.1.50',
      );
    });

    test('falls back to broadcast for 0.0.0.0 (Android broadcast bug)', () {
      expect(
        DiscoveryService.resolveReplyAddress(InternetAddress('0.0.0.0')).address,
        '255.255.255.255',
      );
    });

    test('falls back to broadcast for subnet broadcast senders', () {
      expect(
        DiscoveryService.resolveReplyAddress(
          InternetAddress('192.168.1.255'),
        ).address,
        '255.255.255.255',
      );
    });
  });
}
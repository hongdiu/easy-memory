import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A remote easy_memory Web service discovered on the LAN.
class DiscoveredService {
  final String label;
  final String host;
  final int port;
  final bool authRequired;
  final String platform;

  const DiscoveredService({
    required this.label,
    required this.host,
    required this.port,
    required this.authRequired,
    required this.platform,
  });

  String get url => 'http://$host:$port';
  String get id => '$host:$port';
}

/// UDP broadcast discovery of easy_memory Web services on the LAN.
///
/// ## Server side
/// Call [startListener] while the HTTP server is running. It listens on a
/// fixed UDP port and replies to discovery requests with server metadata.
///
/// ## Client side
/// Call [discover] to send a broadcast probe and collect all replies within
/// the timeout window.
class DiscoveryService {
  static const int _discoveryPort = 50100;
  static const String _magicRequest = 'EASY_MEMORY_DISCOVERY';
  static const Duration _defaultTimeout = Duration(seconds: 3);

  /// Start listening on the discovery UDP port.
  ///
  /// Returns a [DiscoverySession] that the caller must [close] when the
  /// HTTP server stops.
  static Future<DiscoverySession?> startListener({
    required String label,
    required String host,
    required int port,
    required bool authRequired,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
      );
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;

        final request = utf8.decode(datagram.data);
        if (request != _magicRequest) return;

        // Reply unicast to the sender.
        final platform = _detectPlatform();
        final response = jsonEncode({
          'app': 'easy_memory',
          'label': label,
          'host': host,
          'port': port,
          'auth_required': authRequired,
          'platform': platform,
        });
        socket!.send(
          utf8.encode(response),
          datagram.address,
          datagram.port,
        );
      });

      return DiscoverySession._(socket);
    } catch (e) {
      // Non-fatal: discovery unavailable (e.g. port in use, no permission).
      socket?.close();
      return null;
    }
  }

  /// Send a broadcast probe and collect discovered services.
  ///
  /// Returns a list of [DiscoveredService] found within [timeout].
  static Future<List<DiscoveredService>> discover({
    Duration timeout = _defaultTimeout,
  }) async {
    final localIp = await _resolveLocalIp();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0, // OS-assigned port
    );
    socket.broadcastEnabled = true;

    try {
      // Send to the global broadcast address and the subnet broadcast.
      final probe = utf8.encode(_magicRequest);
      final targets = <InternetAddress>[
        InternetAddress('255.255.255.255'),
      ];

      // Compute subnet broadcast address for the /24 prefix.
      final subnetParts = localIp.split('.');
      if (subnetParts.length == 4) {
        subnetParts[3] = '255';
        final subnetBroadcast = subnetParts.join('.');
        if (subnetBroadcast != '255.255.255.255') {
          targets.add(InternetAddress(subnetBroadcast));
        }
      }

      for (final addr in targets) {
        try {
          socket.send(probe, addr, _discoveryPort);
        } catch (_) {
          // Best-effort: some addresses may not be reachable.
        }
      }

      // Collect replies until timeout.
      final seen = <String>{};
      final services = <DiscoveredService>[];
      final completer = Completer<void>();
      StreamSubscription? sub;

      final timer = Timer(timeout, () {
        sub?.cancel();
        if (!completer.isCompleted) completer.complete();
      });

      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;

        try {
          final json = jsonDecode(utf8.decode(datagram.data))
              as Map<String, dynamic>;
          if (json['app'] != 'easy_memory') return;

          final svc = DiscoveredService(
            label: json['label'] as String? ?? '',
            host: json['host'] as String? ?? datagram.address.address,
            port: json['port'] as int? ?? 8080,
            authRequired: json['auth_required'] as bool? ?? false,
            platform: json['platform'] as String? ?? 'unknown',
          );

          // Deduplicate by host:port.
          if (seen.add(svc.id)) {
            services.add(svc);
          }
        } catch (_) {
          // Ignore malformed replies.
        }
      });

      await completer.future;
      return services;
    } finally {
      socket.close();
    }
  }

  /// Resolve the first non-loopback IPv4 address.
  static Future<String> _resolveLocalIp() async {
    if (kIsWeb) return '127.0.0.1';
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 5));
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {
      // non-fatal
    }
    return '127.0.0.1';
  }

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }
}

/// A running discovery UDP listener that must be closed.
class DiscoverySession {
  final RawDatagramSocket _socket;

  DiscoverySession._(this._socket);

  void close() => _socket.close();
}
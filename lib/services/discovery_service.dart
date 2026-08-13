import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'discovery_logger.dart';

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
  /// [udpPort] overrides the discovery port (default 50100). Tests may use
  /// an isolated port to avoid cross-process replies on CI runners where
  /// other test files bind 50100 simultaneously (SO_REUSEADDR can deliver
  /// probes to the wrong listener).
  ///
  /// Returns a [DiscoverySession] that the caller must [close] when the
  /// HTTP server stops.
  static Future<DiscoverySession?> startListener({
    required String label,
    required String host,
    required int port,
    required bool authRequired,
    int udpPort = _discoveryPort,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
      );
      socket.broadcastEnabled = true;
      DiscoveryLogger.log('[Discovery] listener bound on 0.0.0.0:$udpPort '
          'broadcast=${socket.broadcastEnabled}');
    } catch (e) {
      DiscoveryLogger.log('[Discovery] listener bind FAILED on $udpPort: $e');
      socket?.close();
      return null;
    }

    // A non-null snapshot of the socket for use inside the listener
    // closure. A captured nullable local is not reliably promoted across
    // Dart analyzer versions, so avoid relying on it.
    final listener = socket;
    listener.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = listener.receive();
      if (datagram == null) return;

      final request = utf8.decode(datagram.data);
      DiscoveryLogger.log('[Discovery] listener <- ${datagram.address.address}:'
          '${datagram.port} "${request.length > 32 ? '${request.substring(0, 32)}…' : request}"');
      if (request != _magicRequest) return;

      // Reply unicast to the sender, or fall back to broadcast when the
      // reported source address is unusable (known Android bug: broadcast
      // packets arrive with source 0.0.0.0; sending to it is a no-op).
      final replyAddress = resolveReplyAddress(datagram.address);
      if (replyAddress != datagram.address) {
        DiscoveryLogger.log('[Discovery] listener sender address "${datagram.address.address}" '
            'unusable, falling back to broadcast reply');
      }

      final platform = _detectPlatform();
      final response = jsonEncode({
        'app': 'easy_memory',
        'label': label,
        'host': host,
        'port': port,
        'auth_required': authRequired,
        'platform': platform,
      });
      try {
        listener.send(
          utf8.encode(response),
          replyAddress,
          datagram.port,
        );
        DiscoveryLogger.log('[Discovery] listener -> ${replyAddress.address}:${datagram.port} '
            '(~${response.length}B payload)');
      } catch (e) {
        DiscoveryLogger.log('[Discovery] listener send FAILED -> ${replyAddress.address}:'
            '${datagram.port}: $e');
      }
    });

    return DiscoverySession._(listener);
  }

  /// Pick a usable destination for the discovery reply.
  ///
  /// On some platforms (notably Android) broadcast datagrams are reported
  /// with a source address of `0.0.0.0` (or other non-unicast addresses),
  /// which is an invalid send target. In that case we reply to the global
  /// broadcast address — only the probing client holds its ephemeral
  /// source port, so no other receiver is disturbed.
  @visibleForTesting
  static InternetAddress resolveReplyAddress(InternetAddress reported) {
    final addr = reported.address;
    if (addr == '0.0.0.0' ||
        addr == '255.255.255.255' ||
        reported.isLoopback == false && _isNonRoutable(addr)) {
      return InternetAddress('255.255.255.255');
    }
    return reported;
  }

  /// True for addresses that are not a sender's routable unicast address
  /// (e.g. subnet broadcast like 192.168.1.255).
  static bool _isNonRoutable(String addr) {
    final parts = addr.split('.');
    if (parts.length != 4) return false;
    return parts[3] == '255';
  }

  /// Send a broadcast probe and collect discovered services.
  ///
  /// Returns a list of [DiscoveredService] found within [timeout].
  ///
  /// [targetPort] allows overriding the discovery port (default 50100). Tests
  /// may use an unused port to guarantee an empty result.
  ///
  /// Some routers / AP isolation filter broadcast frames between LAN hosts
  /// (PC broadcast never reaches the Android phone) while unicast still
  /// works. So besides the broadcasts we also sweep the local /24 subnet
  /// with unicast probes — the same path already proven to work on
  /// Android↔PC (their replies came back fine).
  static Future<List<DiscoveredService>> discover({
    Duration timeout = _defaultTimeout,
    int targetPort = _discoveryPort,
    bool unicastSweep = true,
  }) async {
    final localIp = await _resolveLocalIp();
    DiscoveryLogger.log('[Discovery] client local IP: $localIp, target port: $targetPort');
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0, // OS-assigned port
    );
    socket.broadcastEnabled = true;
    DiscoveryLogger.log('[Discovery] client bound on ephemeral port ${socket.port}');

    final probe = utf8.encode(_magicRequest);

    try {
      // 1) Broadcast targets: global + subnet broadcast.
      final targets = <InternetAddress>[
        InternetAddress('255.255.255.255'),
      ];
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
          socket.send(probe, addr, targetPort);
          DiscoveryLogger.log('[Discovery] client -> broadcast ${addr.address}:$targetPort '
              '(${probe.length}B)');
        } catch (e) {
          DiscoveryLogger.log('[Discovery] client broadcast send FAILED ${addr.address}: $e');
        }
      }

      // 2) Unicast /24 sweep as a fallback when the router drops broadcasts.
      var swept = 0;
      if (unicastSweep && subnetParts.length == 4) {
        final prefix = '${subnetParts[0]}.${subnetParts[1]}.${subnetParts[2]}';
        for (var host = 2; host <= 254; host++) {
          final ip = '$prefix.$host';
          try {
            socket.send(probe, InternetAddress(ip), targetPort);
            swept++;
          } catch (_) {
            // keep going; some host IPs are not assignable
          }
        }
        DiscoveryLogger.log('[Discovery] client -> unicast sweep $prefix.2-$prefix.254 '
            '($swept probes sent)');
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
          DiscoveryLogger.log('[Discovery] client <- ${datagram.address.address}:'
              '${datagram.port} "${String.fromCharCodes(datagram.data.take(48))}"');
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
            DiscoveryLogger.log('[Discovery] client accepted ${svc.id} '
                '(label=${svc.label.isEmpty ? '?' : svc.label}, '
                'auth=${svc.authRequired}, ${svc.platform})');
          } else {
            DiscoveryLogger.log('[Discovery] client dedup skip ${svc.id}');
          }
        } catch (e) {
          DiscoveryLogger.log('[Discovery] client malformed reply ignored: $e');
        }
      });

      await completer.future;
      // Timer has fired (completer is only completed by it); cancel defensively.
      timer.cancel();
      DiscoveryLogger.log('[Discovery] client scan finished, found ${services.length} '
          'service(s) in ${timeout.inMilliseconds}ms');
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
          if (!addr.isLoopback) {
            DiscoveryLogger.log('[Discovery] local IP via iface ${iface.name}: '
                '${addr.address}');
            return addr.address;
          }
        }
      }
    } catch (e) {
      DiscoveryLogger.log('[Discovery] _resolveLocalIp FAILED (fall back loopback): $e');
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
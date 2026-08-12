import 'dart:convert';

class RemoteEndpoint {
  final String id;
  String label;
  String host;
  int port;
  String apiKey;

  RemoteEndpoint({
    required this.id,
    required this.label,
    required this.host,
    this.port = 8080,
    this.apiKey = '',
  });

  String get url => 'http://$host:$port';

  factory RemoteEndpoint.fromMap(Map<String, dynamic> map) {
    return RemoteEndpoint(
      id: map['id'] as String,
      label: map['label'] as String,
      host: map['host'] as String,
      port: map['port'] as int? ?? 8080,
      apiKey: map['api_key'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'api_key': apiKey,
      };

  RemoteEndpoint copyWith({
    String? id,
    String? label,
    String? host,
    int? port,
    String? apiKey,
  }) {
    return RemoteEndpoint(
      id: id ?? this.id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

/// Serialize a list of [RemoteEndpoint] to a JSON string.
String remoteEndpointsToJson(List<RemoteEndpoint> endpoints) =>
    jsonEncode(endpoints.map((e) => e.toMap()).toList());

/// Deserialize a JSON string to a list of [RemoteEndpoint].
List<RemoteEndpoint> remoteEndpointsFromJson(String json) {
  final list = jsonDecode(json) as List<dynamic>;
  return list.map((e) => RemoteEndpoint.fromMap(e as Map<String, dynamic>)).toList();
}
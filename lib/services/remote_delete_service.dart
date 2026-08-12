import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/remote_endpoint.dart';

/// Result of a remote delete attempt.
class RemoteDeleteResult {
  final bool success;
  final String message;
  final String? warning;
  final int? statusCode;

  const RemoteDeleteResult({
    required this.success,
    required this.message,
    this.warning,
    this.statusCode,
  });
}

/// Service for loading remote endpoint configurations and
/// sending delete requests to remote devices.
class RemoteDeleteService {
  /// Load the list of configured remote endpoints from the persisted JSON file.
  Future<List<RemoteEndpoint>> loadEndpoints() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/remote_endpoints.json');
      if (!await file.exists()) return [];
      final json = await file.readAsString();
      return remoteEndpointsFromJson(json);
    } catch (_) {
      return [];
    }
  }

  /// Send a POST /api/delete request to [endpoint] to delete [filePath].
  ///
  /// Returns a [RemoteDeleteResult] with the outcome.
  Future<RemoteDeleteResult> deleteFile({
    required RemoteEndpoint endpoint,
    required String filePath,
  }) async {
    try {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('${endpoint.url}/api/delete'),
        );
        request.headers.contentType = ContentType.json;
        if (endpoint.apiKey.isNotEmpty) {
          request.headers.set('x-api-key', endpoint.apiKey);
        }
        request.write(jsonEncode({'path': filePath}));

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;

        if (response.statusCode == 200 && data['success'] == true) {
          return RemoteDeleteResult(
            success: true,
            message: '删除成功',
            warning: data['warning'] as String?,
            statusCode: response.statusCode,
          );
        }

        return RemoteDeleteResult(
          success: false,
          message: data['error'] as String? ?? '未知错误',
          statusCode: response.statusCode,
        );
      } finally {
        client.close();
      }
    } on SocketException catch (e) {
      return RemoteDeleteResult(
        success: false,
        message: '无法连接 (${e.message})',
      );
    } on HttpException catch (e) {
      return RemoteDeleteResult(
        success: false,
        message: '请求失败 (${e.message})',
      );
    } catch (e) {
      return RemoteDeleteResult(
        success: false,
        message: '错误: $e',
      );
    }
  }
}
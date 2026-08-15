import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../models/file_record.dart';
import '../models/remote_endpoint.dart';
import '../services/remote_delete_service.dart';

/// 视频预览播放页。
///
/// 支持三种来源：
/// - 本地文件系统路径（桌面端 `C:\...`）→ [VideoPlayerController.file]
/// - Android SAF URI（`content://...`）→ 先拷贝到应用临时目录再播
/// - 远程 HTTP URL（跨设备同步的视频）→ [VideoPlayerController.networkUrl]，流式播放
class VideoPlayerPage extends StatefulWidget {
  final String title;
  final String? localPath;
  final String? remoteUrl;
  final String? apiKey;

  const VideoPlayerPage({
    super.key,
    required this.title,
    this.localPath,
    this.remoteUrl,
    this.apiKey,
  }) : assert(
          (localPath != null) ^ (remoteUrl != null),
          'localPath 与 remoteUrl 必须且只能提供一个',
        );

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _error;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = await _createController();
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowMuting: true,
        allowPlaybackSpeedChanging: false,
        placeholder: const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, errorMessage) => _buildErrorView(
          '播放出错',
          errorMessage.isEmpty ? controller.errorDescription ?? '未知错误' : errorMessage,
        ),
      );
      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
      });
    }
  }

  Future<VideoPlayerController> _createController() async {
    final localPath = widget.localPath;
    if (localPath != null) {
      final filePath = await _prepareLocalFile(localPath);
      return VideoPlayerController.file(File(filePath));
    }
    return VideoPlayerController.networkUrl(
      Uri.parse(widget.remoteUrl!),
      httpHeaders: (widget.apiKey != null && widget.apiKey!.isNotEmpty)
          ? {'x-api-key': widget.apiKey!}
          : const <String, String>{},
    );
  }

  /// Android SAF URI 需先拷贝到临时目录（video_player 的 file() 不支持 content://）。
  /// 其他路径（桌面端、Android /storage/）原样返回。
  Future<String> _prepareLocalFile(String path) async {
    if (!kIsWeb && Platform.isAndroid && path.startsWith('content://')) {
      final dir = await getTemporaryDirectory();
      final safeName =
          widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dest =
          '${dir.path}/em_video_${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await Saf().copyToLocalFile(path, dest);
      return dest;
    }
    return path;
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Center(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const CircularProgressIndicator();
    }
    if (_error != null) {
      return _buildErrorView('无法播放此视频', _error!);
    }
    return Chewie(controller: _chewieController!);
  }

  Widget _buildErrorView(String title, String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

/// 尝试播放视频文件：[record]。
///
/// 规则：
/// - 非视频 ([FileRecord.isVideo] == false) → 返回 false，调用方走原详情逻辑
/// - 本机路径且当前平台支持本地播放 → 进 [VideoPlayerPage] 本地播放，返回 true
/// - Windows 桌面本机视频（video_player 无 Windows 实现）→ 返回 false，进详情页
/// - 远程路径 → 加载 endpoint：无配置提示、单个直放、多个弹选择，返回 true
Future<bool> launchVideoPlayer(
  BuildContext context,
  FileRecord record, {
  required bool Function(String path) isLocalPath,
}) async {
  if (!record.isVideo) return false;

  final local = isLocalPath(record.fullPath);
  if (local) {
    // Windows: video_player 官方无 Windows 实现 → 本地播放暂不支持，进详情页
    if (!kIsWeb && Platform.isWindows) return false;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          title: record.fileName,
          localPath: record.fullPath,
        ),
      ),
    );
    return true;
  }

  // 远程视频：加载 endpoint，决定直放/选择
  final service = RemoteDeleteService();
  final endpoints = await service.loadEndpoints();
  if (!context.mounted) return true;

  if (endpoints.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先在高级页面配置远程地址'),
        duration: Duration(seconds: 3),
      ),
    );
    return true;
  }

  RemoteEndpoint endpoint;
  if (endpoints.length == 1) {
    endpoint = endpoints.first;
  } else {
    final selected = await showModalBottomSheet<RemoteEndpoint>(
      context: context,
      builder: (ctx) => _RemoteEndpointPickerSheet(endpoints: endpoints),
    );
    if (selected == null || !context.mounted) return true;
    endpoint = selected;
  }

  final url =
      '${endpoint.url}/api/file?path=${Uri.encodeQueryComponent(record.fullPath)}';
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VideoPlayerPage(
        title: record.fileName,
        remoteUrl: url,
        apiKey: endpoint.apiKey,
      ),
    ),
  );
  return true;
}

/// 远程播放页的 endpoint 选择 bottom sheet。
class _RemoteEndpointPickerSheet extends StatelessWidget {
  final List<RemoteEndpoint> endpoints;

  const _RemoteEndpointPickerSheet({required this.endpoints});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('选择远程设备', style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ...endpoints.map((e) => ListTile(
                leading: const Icon(Icons.computer),
                title: Text(e.label),
                subtitle: Text(e.host),
                onTap: () => Navigator.of(context).pop(e),
              )),
        ],
      ),
    );
  }
}
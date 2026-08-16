import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  /// 长按倍速档位（SharedPreferences key: `long_press_speed`）
  static const String _speedPrefsKey = 'long_press_speed';
  static const List<double> _speedOptions = [1.5, 2.0, 3.0, 4.0, 5.0];

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _error;
  bool _initializing = true;
  Orientation? _lastOrientation;
  double _longPressSpeed = 3.0;
  bool _longPressing = false;

  @override
  void initState() {
    super.initState();
    _loadLongPressSpeed();
    _init();
  }

  /// 读取用户配置的长按倍速（默认 3.0）。
  Future<void> _loadLongPressSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_speedPrefsKey);
    if (saved != null && mounted) {
      setState(() => _longPressSpeed = saved);
    }
  }

  /// 长按开始：切到配置的倍速。
  void _onLongPressStart(LongPressStartDetails details) {
    _videoController?.setPlaybackSpeed(_longPressSpeed);
    setState(() => _longPressing = true);
  }

  /// 松开 / 手势取消：恢复常速 1x。
  void _restoreNormalSpeed() {
    _videoController?.setPlaybackSpeed(1.0);
    if (_longPressing && mounted) {
      setState(() => _longPressing = false);
    }
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
        allowPlaybackSpeedChanging: true,
        playbackSpeeds: const [1.0, 2.0, 3.0, 5.0],
        placeholder: const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, errorMessage) => _buildErrorView(
          '播放出错',
          errorMessage.isEmpty
              ? (controller.value.errorDescription ?? '未知错误')
              : errorMessage,
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

  /// 是否为移动端平台（Android / iOS），仅在移动端启用横屏沉浸全屏。
  static bool _isMobilePlatform() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape =
        _isMobilePlatform() && orientation == Orientation.landscape;

    // 方向变化时调整系统 UI（仅当方向值变化，避免重复调用）
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isLandscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      });
    }

    if (isLandscape) {
      // 横屏沉浸式全屏：无 AppBar、无状态栏/导航栏，顶部悬浮标题
      return Scaffold(
        body: Stack(
          children: [
            _buildBody(isLandscape: true),
            _buildImmersiveHeader(),
          ],
        ),
      );
    }

    // 竖屏标准页面
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: '长按倍速设置',
            onPressed: _showSpeedSettings,
          ),
        ],
      ),
      body: Center(child: _buildBody()),
    );
  }

  /// 横屏沉浸时顶部悬浮标题层：渐变背景 + 返回按钮 + 视频标题。
  Widget _buildImmersiveHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.speed, color: Colors.white),
                tooltip: '长按倍速设置',
                onPressed: _showSpeedSettings,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody({bool isLandscape = false}) {
    if (_initializing) {
      return const CircularProgressIndicator();
    }
    if (_error != null) {
      return _buildErrorView('无法播放此视频', _error!);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: (_) => _restoreNormalSpeed(),
            onLongPressCancel: _restoreNormalSpeed,
            child: Chewie(controller: _chewieController!),
          ),
        ),
        if (_longPressing)
          Padding(
            padding: EdgeInsets.only(
              right: 16,
            ),
            child: Align(
              alignment: isLandscape ? Alignment.centerRight : Alignment.topRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_formatSpeed(_longPressSpeed)}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 倍速显示格式：整数去小数点（3 → `3`），小数保留一位（1.5 → `1.5`）。
  static String _formatSpeed(double speed) {
    return speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toStringAsFixed(1);
  }

  /// 长按倍速配置层：选择后写入 SharedPreferences，下次长按生效。
  Future<void> _showSpeedSettings() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('长按倍速', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            ..._speedOptions.map((speed) => ListTile(
                  title: Text('${_formatSpeed(speed)}x'),
                  trailing: speed == _longPressSpeed
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(speed),
                )),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedPrefsKey, selected);
    if (!mounted) return;
    setState(() => _longPressSpeed = selected);
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
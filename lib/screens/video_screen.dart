import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import '../models/models.dart';
import '../services/app_controller.dart';
import '../utils/helpers.dart';
import '../widgets/video_card.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.videoId});
  final String videoId;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> with WidgetsBindingObserver, RouteAware {
  bool loading = true;
  bool playerLoading = false;
  bool downloading = false;
  double? downloadProgress;
  String? error;
  String? playerError;
  Map<String, dynamic>? video;
  List<Map<String, dynamic>> comments = const [];
  List<Map<String, dynamic>> related = const [];
  List<PlayableMediaSource> sources = const [];
  int sourceIndex = 0;
  VideoPlayerController? player;
  bool liked = false;
  bool _wasPlayingBeforeAutoPause = false;
  bool _allowRoutePause = true;
  ModalRoute<void>? _subscribedRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        routeObserver.unsubscribe(this);
      }
      routeObserver.subscribe(this, route);
      _subscribedRoute = route;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_subscribedRoute != null) {
      routeObserver.unsubscribe(this);
      _subscribedRoute = null;
    }
    player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Avoid AppLifecycleState.inactive — it fires during route transitions / system UI.
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _autoPause(resumeLater: false);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void didPushNext() {
    // Covered by author page / dialog / etc. Fullscreen opts out via _allowRoutePause.
    if (_allowRoutePause) {
      _autoPause(resumeLater: true);
    }
  }

  @override
  void didPopNext() {
    if (_allowRoutePause) {
      _autoResumeIfNeeded();
    }
  }

  void _autoPause({required bool resumeLater}) {
    final c = player;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      if (resumeLater) {
        _wasPlayingBeforeAutoPause = true;
      } else {
        _wasPlayingBeforeAutoPause = false;
      }
      c.pause();
      if (mounted) setState(() {});
    } else if (!resumeLater) {
      _wasPlayingBeforeAutoPause = false;
    }
  }

  void _autoResumeIfNeeded() {
    final c = player;
    if (!_wasPlayingBeforeAutoPause) return;
    _wasPlayingBeforeAutoPause = false;
    if (c == null || !c.value.isInitialized) return;
    c.play();
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final api = context.read<AppController>();
    setState(() {
      loading = true;
      error = null;
      playerError = null;
    });
    try {
      final detail = asRecord(await api.callApi('fetchVideo', args: {'t': widget.videoId}));
      dynamic commentPayload;
      dynamic relatedPayload;
      try {
        commentPayload = await api.callApi(
          'fetchComments',
          args: {'t': 'video', 'n': widget.videoId},
          query: {'limit': 30, 'page': 1},
        );
      } catch (_) {
        commentPayload = null;
      }
      try {
        relatedPayload = await api.callApi(
          'fetchRelated',
          args: {'t': 'video', 'n': widget.videoId},
          query: {'limit': 8},
        );
      } catch (_) {
        relatedPayload = null;
      }
      final fileUrl = '${detail['fileUrl'] ?? ''}';
      List<PlayableMediaSource> nextSources = const [];
      if (fileUrl.isNotEmpty) {
        nextSources = await api.mediaSources(fileUrl);
      }
      unawaited(api.callApi('sendView', args: {'t': 'video', 'n': widget.videoId}, body: {}).catchError((_) => null));
      if (!mounted) return;
      setState(() {
        video = detail;
        comments = commentPayload == null ? const [] : listResults(commentPayload);
        related = relatedPayload == null ? const [] : listResults(relatedPayload);
        sources = nextSources;
        liked = detail['liked'] == true;
        loading = false;
      });
      if (nextSources.isNotEmpty) {
        unawaited(_startPlayer(nextSources, 0, autoFallback: true));
      } else {
        setState(() => playerError = '没有可播放源');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _startPlayer(List<PlayableMediaSource> list, int index, {bool autoFallback = false}) async {
    if (index < 0 || index >= list.length) {
      if (!mounted) return;
      setState(() {
        playerLoading = false;
        playerError = '全部画质都无法打开';
      });
      return;
    }

    final old = player;
    setState(() {
      player = null;
      playerLoading = true;
      playerError = null;
      sourceIndex = index;
    });
    await old?.dispose();

    final source = list[index];
    final next = VideoPlayerController.networkUrl(
      Uri.parse(source.url),
      httpHeaders: const {
        'Accept': '*/*',
        'User-Agent': 'iwara-signal-desk/0.1',
      },
    );
    try {
      await next.initialize().timeout(const Duration(seconds: 45));
      await next.setLooping(true);
      await next.play();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        player = next;
        playerLoading = false;
        playerError = null;
      });
    } catch (e) {
      await next.dispose();
      if (!mounted) return;
      if (autoFallback && index + 1 < list.length) {
        await _startPlayer(list, index + 1, autoFallback: true);
        return;
      }
      setState(() {
        playerLoading = false;
        playerError = '播放失败: $e';
      });
    }
  }

  Future<void> _toggleLike() async {
    final api = context.read<AppController>();
    if (api.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    try {
      await api.callApi(liked ? 'unlike' : 'like', args: {'t': 'video', 'n': widget.videoId});
      setState(() => liked = !liked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _switchSource(PlayableMediaSource source) async {
    final index = sources.indexWhere((item) => item.url == source.url && item.label == source.label);
    await _startPlayer(sources, index < 0 ? 0 : index, autoFallback: false);
  }

  Future<void> _openFullscreen() async {
    final current = player;
    if (current == null || !current.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('视频尚未就绪')));
      return;
    }
    // Fullscreen reuses the same controller — do not pause on route push.
    _allowRoutePause = false;
    try {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (_, __, ___) => FullscreenVideoPage(controller: current),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        ),
      );
    } finally {
      _allowRoutePause = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _download() async {
    final api = context.read<AppController>();
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可下载源')));
      return;
    }
    final source = sources[sourceIndex.clamp(0, sources.length - 1)];
    final downloadUrl = source.downloadUrl?.isNotEmpty == true ? source.downloadUrl! : source.url;
    final title = sanitizeFilename('${video?['title'] ?? widget.videoId}');
    final label = sanitizeFilename(source.label);
    final filename = '${title}_$label.mp4';

    setState(() {
      downloading = true;
      downloadProgress = null;
    });
    try {
      final file = await api.downloadMedia(
        url: downloadUrl,
        filename: filename,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            downloadProgress = total == null || total <= 0 ? null : received / total;
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          downloading = false;
          downloadProgress = null;
        });
      }
    }
  }

  Widget _playerPane() {
    return VideoSurface(
      controller: player,
      loading: playerLoading,
      errorText: playerError,
      maxHeightFactor: 0.72,
      onTogglePlay: () {
        final c = player;
        if (c == null || !c.value.isInitialized) return;
        setState(() {
          if (c.value.isPlaying) {
            c.pause();
          } else {
            c.play();
          }
        });
      },
      onFullscreen: player?.value.isInitialized == true ? _openFullscreen : null,
      showInlineControls: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<AppController>();
    final author = video?['user'] is Map ? unwrapUser(video!['user']) : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(video == null ? '视频' : '${video!['title'] ?? '视频'}'),
        actions: [
          IconButton(
            tooltip: '全屏',
            onPressed: player?.value.isInitialized == true ? _openFullscreen : null,
            icon: const Icon(Icons.fullscreen),
          ),
          IconButton(
            tooltip: '下载',
            onPressed: downloading || sources.isEmpty ? null : _download,
            icon: downloading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, value: downloadProgress),
                  )
                : const Icon(Icons.download),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
                _playerPane(),
                if (downloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: downloadProgress),
                  const SizedBox(height: 4),
                  Text(downloadProgress == null ? '下载中…' : '下载中 ${(downloadProgress! * 100).toStringAsFixed(0)}%'),
                ],
                if (sources.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < sources.length; i++)
                        ChoiceChip(
                          label: Text(sources[i].label),
                          selected: i == sourceIndex,
                          onSelected: playerLoading ? null : (_) => _switchSource(sources[i]),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text('${video?['title'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '播放 ${formatCount(video?['numViews'])} · 点赞 ${formatCount(video?['numLikes'])}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                if (author != null && author.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text(_initial(displayName(author)))),
                    title: Text(displayName(author)),
                    subtitle: Text('@${author['username'] ?? author['id'] ?? ''}'),
                    onTap: () {
                      final username = '${author['username'] ?? author['id'] ?? ''}';
                      if (username.isNotEmpty) {
                        Navigator.of(context).pushNamed('/account/$username');
                      }
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _toggleLike,
                      child: Text(liked ? '取消点赞' : '点赞'),
                    ),
                    FilledButton.tonal(
                      onPressed: player?.value.isInitialized == true ? _openFullscreen : null,
                      child: const Text('全屏'),
                    ),
                    FilledButton.tonal(
                      onPressed: downloading || sources.isEmpty ? null : _download,
                      child: Text(downloading ? '下载中' : '下载'),
                    ),
                    if (playerError != null)
                      OutlinedButton(
                        onPressed: sources.isEmpty ? null : () => _startPlayer(sources, sourceIndex, autoFallback: false),
                        child: const Text('重试播放'),
                      ),
                  ],
                ),
                if ((video?['body'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${video?['body']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                ],
                const SizedBox(height: 20),
                Text('评论', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (comments.isEmpty) const Text('暂无评论'),
                ...comments.map((item) {
                  final user = item['user'] is Map ? unwrapUser(item['user']) : null;
                  return Card(
                    child: ListTile(
                      title: Text(user == null ? '用户' : displayName(user)),
                      subtitle: Text('${item['body'] ?? item['message'] ?? ''}'),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                Text('相关', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (related.isEmpty) const Text('暂无相关视频'),
                ...related.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: VideoCard(
                      title: '${item['title'] ?? '未命名'}',
                      subtitle: formatCount(item['numViews']),
                      thumbnailUrl: api.thumbnailUrl(item),
                      onTap: () => Navigator.of(context).pushReplacementNamed('/video/${item['id']}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _initial(String value) {
    final text = value.trim();
    if (text.isEmpty) return '?';
    return text.characters.first.toUpperCase();
  }
}

class VideoSurface extends StatelessWidget {
  const VideoSurface({
    super.key,
    required this.controller,
    this.loading = false,
    this.errorText,
    this.maxHeightFactor = 0.72,
    this.onTogglePlay,
    this.onFullscreen,
    this.showInlineControls = true,
    this.fills = false,
  });

  final VideoPlayerController? controller;
  final bool loading;
  final String? errorText;
  final double maxHeightFactor;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onFullscreen;
  final bool showInlineControls;
  final bool fills;

  double _aspectRatio(VideoPlayerController c) {
    final raw = c.value.aspectRatio;
    if (raw > 0.01 && raw < 100) return raw;
    final size = c.value.size;
    if (size.width > 0 && size.height > 0) return size.width / size.height;
    return 16 / 9;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      final placeholderHeight = MediaQuery.sizeOf(context).width * 9 / 16;
      return Container(
        color: Colors.black,
        width: double.infinity,
        height: fills ? double.infinity : placeholderHeight.clamp(180.0, MediaQuery.sizeOf(context).height * maxHeightFactor),
        alignment: Alignment.center,
        child: loading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载视频流…', style: TextStyle(color: Colors.white70)),
                ],
              )
            : Text(
                errorText ?? '暂无播放源',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, value, _) {
        final ar = _aspectRatio(c);
        final video = AspectRatio(aspectRatio: ar, child: VideoPlayer(c));

        if (fills) {
          return ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: video),
                if (showInlineControls)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _controls(c, value, showFullscreen: false),
                  ),
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final maxH = MediaQuery.sizeOf(context).height * maxHeightFactor;
            var boxW = maxW;
            var boxH = boxW / ar;
            if (boxH > maxH) {
              boxH = maxH;
              boxW = boxH * ar;
            }
            return Container(
              width: maxW,
              height: boxH,
              color: Colors.black,
              alignment: Alignment.center,
              child: SizedBox(
                width: boxW,
                height: boxH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    video,
                    if (showInlineControls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _controls(c, value, showFullscreen: true),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _controls(VideoPlayerController c, VideoPlayerValue value, {required bool showFullscreen}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoProgressIndicator(
            c,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            colors: const VideoProgressColors(
              playedColor: Colors.white,
              bufferedColor: Colors.white38,
              backgroundColor: Colors.white24,
            ),
          ),
          Row(
            children: [
              IconButton(
                color: Colors.white,
                onPressed: onTogglePlay,
                icon: Icon(value.isPlaying ? Icons.pause_circle : Icons.play_circle),
              ),
              const Spacer(),
              if (showFullscreen && onFullscreen != null)
                IconButton(
                  color: Colors.white,
                  tooltip: '全屏',
                  onPressed: onFullscreen,
                  icon: const Icon(Icons.fullscreen),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class FullscreenVideoPage extends StatefulWidget {
  const FullscreenVideoPage({super.key, required this.controller});
  final VideoPlayerController controller;

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> with WidgetsBindingObserver {
  bool showControls = true;
  Timer? hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Force orientation by video aspect: landscape content -> landscape screen.
    // Allowing all orientations does NOT auto-rotate on most devices.
    final ar = widget.controller.value.aspectRatio;
    if (ar > 0 && ar < 1) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    widget.controller.addListener(_onTick);
    _scheduleHide();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (widget.controller.value.isPlaying) {
        setState(() => showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => showControls = !showControls);
    if (showControls) _scheduleHide();
  }

  void _revealControls() {
    setState(() => showControls = true);
    _scheduleHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (widget.controller.value.isPlaying) {
          widget.controller.pause();
          if (mounted) setState(() {});
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    hideTimer?.cancel();
    widget.controller.removeListener(_onTick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoSurface(
              controller: controller,
              fills: true,
              showInlineControls: showControls,
              onTogglePlay: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
                _revealControls();
              },
            ),
            if (showControls)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                left: 4,
                child: IconButton(
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            if (showControls)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                right: 4,
                child: IconButton(
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.fullscreen_exit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

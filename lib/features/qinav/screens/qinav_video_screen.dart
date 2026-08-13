import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../services/qinav_controller.dart';
import '../widgets/qinav_video_card.dart';

class QinavVideoScreen extends StatefulWidget {
  const QinavVideoScreen({super.key, required this.vid});
  final int vid;

  @override
  State<QinavVideoScreen> createState() => _QinavVideoScreenState();
}

class _QinavVideoScreenState extends State<QinavVideoScreen> {
  bool loading = true;
  String? error;
  QinavVideoDetail? detail;
  QinavPlayback? playback;
  VideoPlayerController? player;
  bool playReady = false;
  String? playSource;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<QinavController>();
    setState(() {
      loading = true;
      error = null;
      playReady = false;
      playSource = null;
    });
    try {
      final d = await api.fetchDetail(widget.vid);
      final p = await api.fetchPlayback(widget.vid);
      if (!mounted) return;
      setState(() {
        detail = d;
        playback = p;
        loading = false;
      });
      await _setupPlayer(api, p);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> _setupPlayer(QinavController api, QinavPlayback play) async {
    await player?.dispose();
    player = null;
    playReady = false;
    if (!mounted) return;
    if (play.url.isEmpty) {
      setState(() => error = '无法解析可播放地址');
      return;
    }
    final source = api.proxiedPlay(play.url);
    playSource = source;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(source),
      formatHint: VideoFormat.hls,
      httpHeaders: const {
        'Accept': '*/*',
        'User-Agent': 'signal-desk-qinav/0.1',
      },
    );
    player = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() {
        playReady = true;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '播放器初始化失败: $e'
            '${play.reachable ? '' : '\n（CDN 探测未通过，已回退原地址）'}\n源: $source';
      });
    }
  }

  Future<void> _openFullscreen() async {
    final current = player;
    if (current == null || !current.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('视频尚未就绪')));
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _QinavFullscreenPage(controller: current),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<QinavController>();
    final d = detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.title.isNotEmpty == true ? d!.title : '视频 ${widget.vid}'),
        actions: [
          IconButton(
            tooltip: '全屏',
            onPressed: playReady ? _openFullscreen : null,
            icon: const Icon(Icons.fullscreen),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                AspectRatio(
                  aspectRatio: playReady && player != null ? player!.value.aspectRatio : 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child: playReady && player != null
                        ? Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              VideoPlayer(player!),
                              VideoProgressIndicator(player!, allowScrubbing: true),
                              Align(
                                alignment: Alignment.center,
                                child: IconButton(
                                  iconSize: 48,
                                  color: Colors.white,
                                  onPressed: () {
                                    setState(() {
                                      if (player!.value.isPlaying) {
                                        player!.pause();
                                      } else {
                                        player!.play();
                                      }
                                    });
                                  },
                                  icon: Icon(player!.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 28,
                                child: IconButton(
                                  tooltip: '全屏',
                                  color: Colors.white,
                                  onPressed: _openFullscreen,
                                  icon: const Icon(Icons.fullscreen),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                error ??
                                    (playback?.reachable == false
                                        ? 'CDN 探测失败，正在尝试原地址…'
                                        : '准备播放…'),
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (error != null) SelectableText(error!, style: const TextStyle(color: Colors.redAccent)),
                if (playSource != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    '本地代理: $playSource',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                  ),
                ],
                if (d != null) ...[
                  Text(d.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('赞 ${d.zan} · 踩 ${d.cai} · 收藏 ${d.favorites}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                  if (d.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(d.description),
                  ],
                  if (playback != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      playback!.reachable ? '播放源已就绪' : '播放源可能不可达',
                      style: TextStyle(color: playback!.reachable ? Colors.greenAccent : Colors.amber),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('相关推荐', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final item in d.related)
                    if (item.vid != widget.vid)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: QinavVideoCard(
                          title: item.title,
                          subtitle: '${item.views} 播放 · ${item.likes} 赞',
                          duration: item.duration,
                          thumbnailUrl: api.proxiedImage(item.cover),
                          onTap: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => QinavVideoScreen(vid: item.vid)),
                            );
                          },
                        ),
                      ),
                ],
              ],
            ),
    );
  }
}

class _QinavFullscreenPage extends StatefulWidget {
  const _QinavFullscreenPage({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_QinavFullscreenPage> createState() => _QinavFullscreenPageState();
}

class _QinavFullscreenPageState extends State<_QinavFullscreenPage> {
  bool showControls = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => showControls = !showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: c.value.isInitialized
                  ? AspectRatio(aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio, child: VideoPlayer(c))
                  : const CircularProgressIndicator(),
            ),
            if (showControls) ...[
              Align(
                alignment: Alignment.center,
                child: IconButton(
                  iconSize: 64,
                  color: Colors.white,
                  onPressed: () {
                    setState(() {
                      if (c.value.isPlaying) {
                        c.pause();
                      } else {
                        c.play();
                      }
                    });
                  },
                  icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 8,
                child: VideoProgressIndicator(c, allowScrubbing: true),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                left: 4,
                child: IconButton(
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
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
          ],
        ),
      ),
    );
  }
}

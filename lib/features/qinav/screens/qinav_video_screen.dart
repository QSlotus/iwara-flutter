import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:signal_desk/core/player/shared_video_surface.dart';

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
  bool playerLoading = false;
  String? error;
  String? playerError;
  QinavVideoDetail? detail;
  QinavPlayback? playback;
  VideoPlayerController? player;
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
      playerLoading = false;
      error = null;
      playerError = null;
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
    if (!mounted) return;
    if (play.url.isEmpty) {
      setState(() {
        playerError = '\u65e0\u6cd5\u89e3\u6790\u53ef\u64ad\u653e\u5730\u5740';
      });
      return;
    }

    final source = api.proxiedPlay(play.url);
    playSource = source;
    setState(() {
      playerLoading = true;
      playerError = null;
    });

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
        playerLoading = false;
        playerError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        playerLoading = false;
        playerError = '\u64ad\u653e\u5668\u521d\u59cb\u5316\u5931\u8d25: $e'
            '${play.reachable ? '' : '\n\uff08CDN \u63a2\u6d4b\u672a\u901a\u8fc7\uff0c\u5df2\u56de\u9000\u539f\u5730\u5740\uff09'}\n\u6e90: $source';
      });
    }
  }

  Future<void> _openFullscreen() async {
    final current = player;
    if (current == null || !current.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u89c6\u9891\u5c1a\u672a\u5c31\u7eea')),
      );
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => FullscreenVideoPage(controller: current),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _playerPane() {
    return VideoSurface(
      controller: player,
      loading: playerLoading,
      errorText: playerError ??
          (playback?.reachable == false ? 'CDN \u63a2\u6d4b\u5931\u8d25\uff0c\u6b63\u5728\u5c1d\u8bd5\u539f\u5730\u5740\u2026' : null),
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
    final api = context.watch<QinavController>();
    final d = detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.title.isNotEmpty == true ? d!.title : '\u89c6\u9891 ${widget.vid}'),
        actions: [
          IconButton(
            tooltip: '\u5168\u5c4f',
            onPressed: player?.value.isInitialized == true ? _openFullscreen : null,
            icon: const Icon(Icons.fullscreen),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
                _playerPane(),
                if (playSource != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    '\u672c\u5730\u4ee3\u7406: $playSource',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                  ),
                ],
                if (d != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    d.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\u8d5e ${d.zan} \u00b7 \u8e29 ${d.cai} \u00b7 \u6536\u85cf ${d.favorites}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  if (d.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(d.description),
                  ],
                  if (playback != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      playback!.reachable ? '\u64ad\u653e\u6e90\u5df2\u5c31\u7eea' : '\u64ad\u653e\u6e90\u53ef\u80fd\u4e0d\u53ef\u8fbe',
                      style: TextStyle(color: playback!.reachable ? Colors.greenAccent : Colors.amber),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('\u76f8\u5173\u63a8\u8350', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final item in d.related)
                    if (item.vid != widget.vid)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: QinavVideoCard(
                          title: item.title,
                          subtitle: '${item.views} \u64ad\u653e \u00b7 ${item.likes} \u8d5e',
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

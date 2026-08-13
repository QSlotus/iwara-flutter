import 'package:flutter/material.dart';
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
    });
    try {
      final d = await api.fetchDetail(widget.vid);
      final p = await api.fetchPlayback(widget.vid);
      setState(() {
        detail = d;
        playback = p;
        loading = false;
      });
      await _setupPlayer(api, p);
    } catch (e) {
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
    if (!play.reachable && play.url.isEmpty) {
      setState(() => error = '无法解析可播放地址');
      return;
    }
    final source = api.proxiedMaster(play.url);
    final controller = VideoPlayerController.networkUrl(Uri.parse(source));
    player = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() => playReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '播放器初始化失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<QinavController>();
    final d = detail;
    return Scaffold(
      appBar: AppBar(title: Text(d?.title.isNotEmpty == true ? d!.title : '视频 ${widget.vid}')),
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
                            ],
                          )
                        : Center(
                            child: Text(
                              error ?? (playback?.reachable == false ? 'CDN 探测失败，已尝试回退原地址' : '准备播放…'),
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
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

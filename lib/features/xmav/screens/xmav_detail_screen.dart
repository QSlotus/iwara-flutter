import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:signal_desk/core/player/shared_video_surface.dart';
import 'package:signal_desk/features/xmav/models/models.dart';
import 'package:signal_desk/features/xmav/services/xmav_controller.dart';
import 'package:signal_desk/features/xmav/services/xmav_http.dart';

class XmavDetailScreen extends StatefulWidget {
  const XmavDetailScreen({super.key, required this.item});

  final XmavVideoItem item;

  @override
  State<XmavDetailScreen> createState() => _XmavDetailScreenState();
}

class _XmavDetailScreenState extends State<XmavDetailScreen> {
  bool playerLoading = false;
  bool detailLoading = false;
  String? playerError;
  VideoPlayerController? player;
  XmavPlayback? playback;
  late XmavVideoItem detail;

  @override
  void initState() {
    super.initState();
    detail = widget.item;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    final api = context.read<XmavController>();
    if (!api.ready) return;
    setState(() => detailLoading = true);
    try {
      final d = await api.fetchDetail(widget.item.id);
      if (!mounted) return;
      setState(() {
        detail = XmavVideoItem(
          id: d.id,
          title: d.title.isNotEmpty ? d.title : widget.item.title,
          cover: d.cover.isNotEmpty ? d.cover : widget.item.cover,
          blurb: d.blurb.isNotEmpty ? d.blurb : widget.item.blurb,
          actor: d.actor.isNotEmpty ? d.actor : widget.item.actor,
          vodClass: d.vodClass.isNotEmpty ? d.vodClass : widget.item.vodClass,
          remarks: d.remarks.isNotEmpty ? d.remarks : widget.item.remarks,
          time: d.time.isNotEmpty ? d.time : widget.item.time,
          hits: d.hits > 0 ? d.hits : widget.item.hits,
          score: d.score.isNotEmpty ? d.score : widget.item.score,
          typeId: d.typeId > 0 ? d.typeId : widget.item.typeId,
          duration: d.duration.isNotEmpty ? d.duration : widget.item.duration,
        );
        detailLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => detailLoading = false);
    }
  }

  Future<void> _play() async {
    final api = context.read<XmavController>();
    setState(() {
      playerLoading = true;
      playerError = null;
    });
    try {
      final p = await api.fetchPlayback(widget.item.id);
      if (!mounted) return;
      playback = p;
      await player?.dispose();
      final lower = p.url.toLowerCase();
      final isHls = lower.contains('m3u8') || lower.contains('/hls/');
      // Direct CDN play (no local proxy). Relative AES key/segments resolve against playlist URL.
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(p.url),
        formatHint: isHls ? VideoFormat.hls : null,
        httpHeaders: {
          'User-Agent': XmavHttp.userAgent,
          'Referer': api.base.isNotEmpty ? '${api.base}/' : 'http://xmav.vip/',
          'Origin': api.base.isNotEmpty ? api.base : 'http://xmav.vip',
          'Accept': '*/*',
        },
      );
      player = controller;
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
        playerError = '播放器初始化失败: $e';
      });
    }
  }

  Future<void> _openFullscreen() async {
    final c = player;
    if (c == null || !c.value.isInitialized) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FullscreenVideoPage(controller: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = detail;
    final title = item.title.isEmpty ? '视频 ${item.id}' : item.title;

    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (player != null && player!.value.isInitialized)
            VideoSurface(
              controller: player,
              onFullscreen: _openFullscreen,
            )
          else if (item.cover.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item.cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, size: 40),
                  ),
                ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Icon(Icons.movie_outlined, size: 40),
              ),
            ),
          const SizedBox(height: 12),
          if (playerLoading || detailLoading) const LinearProgressIndicator(minHeight: 2),
          if (playerError != null) ...[
            const SizedBox(height: 8),
            Text(playerError!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.vodClass.isNotEmpty) Chip(label: Text(item.vodClass)),
              if (item.hits > 0) Chip(label: Text('热度 ${item.hits}')),
              if (item.score.isNotEmpty && item.score != '0.0') Chip(label: Text('评分 ${item.score}')),
              if (item.time.isNotEmpty) Chip(label: Text(item.time)),
            ],
          ),
          if (item.actor.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('演员: ${item.actor}'),
          ],
          if (item.blurb.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(item.blurb, style: TextStyle(color: Colors.white.withValues(alpha: 0.78))),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: playerLoading ? null : _play,
            icon: const Icon(Icons.play_arrow),
            label: Text(player == null ? '播放' : '重新播放'),
          ),
          if (playback != null) ...[
            const SizedBox(height: 8),
            Text(
              playback!.usedParse
                  ? '线路: ${playback!.from} (parse)'
                  : '线路: ${playback!.from.isEmpty ? '直链' : playback!.from}',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ],
      ),
    );
  }
}

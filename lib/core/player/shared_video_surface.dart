import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

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

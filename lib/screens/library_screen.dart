import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import '../utils/helpers.dart';
import '../widgets/video_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool loading = true;
  bool loadingMore = false;
  String? error;
  List<Map<String, dynamic>> likes = const [];
  int page = 0;
  bool hasMore = true;
  static const pageSize = 24;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    final api = context.read<AppController>();
    if (api.token.isEmpty) {
      setState(() {
        loading = false;
        likes = const [];
        error = null;
        hasMore = false;
      });
      return;
    }

    if (reset) {
      setState(() {
        loading = true;
        error = null;
        page = 1;
        likes = const [];
        hasMore = true;
      });
    } else {
      if (!hasMore || loadingMore) return;
      setState(() => loadingMore = true);
    }

    try {
      // Web library uses 1-based paging for /favorites/videos.
      final nextPage = reset ? 1 : page;
      final payload = await api.callApi(
        'fetchFavorites',
        args: {'t': 'videos'},
        query: {'limit': pageSize, 'page': nextPage},
      );

      final batch = listVideos(payload);
      // de-dupe across pages
      final merged = <Map<String, dynamic>>[
        if (!reset) ...likes,
      ];
      final seen = <String>{for (final item in merged) '${item['id'] ?? item['slug']}'};
      for (final item in batch) {
        final id = '${item['id'] ?? item['slug']}';
        if (seen.add(id)) merged.add(item);
      }

      if (!mounted) return;
      setState(() {
        likes = merged;
        page = nextPage + 1;
        hasMore = batch.length >= pageSize;
        loading = false;
        loadingMore = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
        loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('资料库'),
        actions: [
          IconButton(
            onPressed: loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null) ...[
                    Text(error!, style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 8),
                  ],
                  if (api.token.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('登录后查看已点赞视频'),
                        subtitle: Text('请到账户页登录 Iwara 账号'),
                      ),
                    )
                  else ...[
                    Text('我点赞的视频 (${likes.length})', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (likes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text('还没有点赞视频。在视频详情页点“点赞”后会出现在这里。'),
                      ),
                    ...likes.map(
                      (video) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: VideoCard(
                          title: '${video['title'] ?? '未命名'}',
                          subtitle: '${formatCount(video['numViews'])} 播放 · ${formatCount(video['numLikes'])} 点赞',
                          thumbnailUrl: api.thumbnailUrl(video),
                          onTap: () {
                            final id = '${video['id'] ?? ''}'.trim();
                            if (id.isEmpty) return;
                            Navigator.of(context).pushNamed('/video/$id');
                          },
                        ),
                      ),
                    ),
                    if (hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: FilledButton.tonal(
                            onPressed: loadingMore ? null : () => _load(reset: false),
                            child: Text(loadingMore ? '加载中…' : '加载更多'),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

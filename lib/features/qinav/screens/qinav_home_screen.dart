import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/qinav_controller.dart';
import '../widgets/qinav_video_card.dart';
import 'qinav_video_screen.dart';

class QinavHomeScreen extends StatefulWidget {
  const QinavHomeScreen({super.key});

  @override
  State<QinavHomeScreen> createState() => _QinavHomeScreenState();
}

class _QinavHomeScreenState extends State<QinavHomeScreen> {
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<QinavController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qinav'),
        actions: [
          if (api.onExitModule != null)
            TextButton(onPressed: api.onExitModule, child: const Text('退出项目')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: '搜索关键词',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      final kw = value.trim();
                      if (kw.isEmpty) return;
                      api.setFeed(QinavFeed.search, keyword: kw);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final kw = searchController.text.trim();
                    if (kw.isEmpty) return;
                    api.setFeed(QinavFeed.search, keyword: kw);
                  },
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _chip(api, '最新', QinavFeed.latest),
                _chip(api, '热门', QinavFeed.hot),
                _chip(api, '推荐', QinavFeed.like),
                _chip(api, '排行', QinavFeed.rank),
                for (final entry in qinavCategories.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: api.feed == QinavFeed.category && api.categoryId == entry.key,
                      onSelected: (_) => api.setFeed(QinavFeed.category, cid: entry.key),
                    ),
                  ),
              ],
            ),
          ),
          if (api.feed == QinavFeed.search && api.searchKeyword.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('搜索: ${api.searchKeyword}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              ),
            ),
          if (api.lastError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(api.lastError!, style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: api.loading && api.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: api.refreshFeed,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: api.items.length + 1,
                      itemBuilder: (context, index) {
                        if (index >= api.items.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: api.feed == QinavFeed.rank
                                  ? const SizedBox.shrink()
                                  : FilledButton.tonal(
                                      onPressed: api.loadingMore ? null : api.loadMore,
                                      child: Text(api.loadingMore ? '加载中…' : '加载更多'),
                                    ),
                            ),
                          );
                        }
                        final item = api.items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: QinavVideoCard(
                            title: item.title.isEmpty ? '未命名' : item.title,
                            subtitle: '${_fmt(item.views)} 播放 · ${_fmt(item.likes)} 赞 · ${item.time}',
                            duration: item.duration,
                            thumbnailUrl: api.proxiedImage(item.cover),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => QinavVideoScreen(vid: item.vid)),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(QinavController api, String label, QinavFeed feed) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: api.feed == feed,
        onSelected: (_) => api.setFeed(feed),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

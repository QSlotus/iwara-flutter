import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import '../utils/helpers.dart';
import '../widgets/video_card.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final controller = TextEditingController();
  String sort = 'newest';
  int page = 0;
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> videos = const [];
  List<Map<String, dynamic>> users = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppController>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final query = controller.text.trim();
      final dynamic videoPayload;
      if (query.isEmpty) {
        videoPayload = await api.callApi('fetchVideos', query: {
          'limit': 20,
          'page': page,
          if (sort != 'newest') 'sort': sort,
        });
      } else {
        videoPayload = await api.callApi('fetchSearchResults', query: {
          'type': 'videos',
          'query': query,
          'sort': sort == 'newest' ? 'date' : (sort == 'trending' ? 'relevance' : sort),
          'limit': 20,
          'page': page,
        });
      }
      dynamic userPayload;
      if (query.isNotEmpty) {
        userPayload = await api.callApi('fetchSearchResults', query: {
          'type': 'users',
          'query': query,
          'sort': 'relevance',
          'limit': 5,
          'page': 0,
        });
      }
      if (!mounted) return;
      setState(() {
        videos = listResults(videoPayload);
        users = userPayload == null ? const [] : listResults(userPayload);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('探索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: '搜索视频 / 用户', prefixIcon: Icon(Icons.search)),
                    onSubmitted: (_) {
                      page = 0;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: sort,
                  items: const [
                    DropdownMenuItem(value: 'newest', child: Text('最新')),
                    DropdownMenuItem(value: 'trending', child: Text('趋势')),
                    DropdownMenuItem(value: 'views', child: Text('播放')),
                    DropdownMenuItem(value: 'likes', child: Text('喜欢')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => sort = value);
                    page = 0;
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
          if (users.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, index) {
                  final user = users[index];
                  return ActionChip(
                    label: Text(displayName(user)),
                    onPressed: () => Navigator.of(context).pushNamed('/account/${user['username'] ?? user['id']}'),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: users.length,
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: videos.length + 1,
                      itemBuilder: (context, index) {
                        if (index == videos.length) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: page == 0
                                    ? null
                                    : () {
                                        setState(() => page -= 1);
                                        _load();
                                      },
                                child: const Text('上一页'),
                              ),
                              Text('第 ${page + 1} 页'),
                              TextButton(
                                onPressed: () {
                                  setState(() => page += 1);
                                  _load();
                                },
                                child: const Text('下一页'),
                              ),
                            ],
                          );
                        }
                        final video = videos[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: VideoCard(
                            title: '${video['title'] ?? '未命名'}',
                            subtitle: '${formatCount(video['numViews'])} 播放',
                            thumbnailUrl: api.thumbnailUrl(video),
                            onTap: () => Navigator.of(context).pushNamed('/video/${video['id']}'),
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
}

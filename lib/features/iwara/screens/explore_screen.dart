import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import '../utils/helpers.dart';
import '../widgets/video_card.dart';

/// Extract an Iwara video id from free text / URL, or null if it looks like a keyword.
String? parseIwaraVideoId(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final fromUrl = RegExp(
    r'(?:iwara\.tv)?/(?:video|videos)/([A-Za-z0-9_-]+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (fromUrl != null) return fromUrl.group(1);

  // Bare id: short alphanumeric token without spaces / CJK.
  if (RegExp(r'^[A-Za-z0-9_-]{5,40}$').hasMatch(text)) {
    return text;
  }
  return null;
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final controller = TextEditingController();
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> videos = const [];
  List<Map<String, dynamic>> users = const [];
  String sort = 'newest';
  int page = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _openById(String id) async {
    final videoId = id.trim();
    if (videoId.isEmpty) return;
    await Navigator.of(context).pushNamed('/video/$videoId');
  }

  Future<void> _load() async {
    final api = context.read<AppController>();
    final query = controller.text.trim();

    // Prefer direct open when input is a video id / video URL.
    final directId = parseIwaraVideoId(query);
    if (directId != null) {
      await _openById(directId);
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      late final Object videoPayload;
      Object? userPayload;
      if (query.isEmpty) {
        videoPayload = await api.callApi('fetchVideos', query: {
          'limit': 24,
          'page': page,
          'sort': sort,
        });
      } else {
        // Prefer official /search; AppController falls back when Iwara returns errors.serverError.
        videoPayload = await api.searchResults(
          type: 'video',
          query: query,
          limit: 24,
          page: page,
          sort: sort,
        );
        try {
          userPayload = await api.searchResults(
            type: 'user',
            query: query,
            limit: 12,
            page: 0,
          );
        } catch (_) {
          // User section is optional; keep video results even if user fallback fails.
          userPayload = null;
        }
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

  Future<void> _openIdAction() async {
    final id = parseIwaraVideoId(controller.text) ?? controller.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入视频 ID 或链接')));
      return;
    }
    if (parseIwaraVideoId(id) == null && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法解析为视频 ID')));
      return;
    }
    await _openById(parseIwaraVideoId(id) ?? id);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: '搜索视频 / 用户，或粘贴视频 ID / 链接',
                          prefixIcon: Icon(Icons.search),
                        ),
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          page = 0;
                          _load();
                        },
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('搜索'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openIdAction,
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('打开视频 ID'),
                      ),
                    ],
                  ),
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

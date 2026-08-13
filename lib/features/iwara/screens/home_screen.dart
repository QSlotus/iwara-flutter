import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import '../utils/helpers.dart';
import '../widgets/video_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> feed = const [];
  String? lastToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.watch<AppController>().token;
    if (lastToken == null) {
      lastToken = token;
      return;
    }
    if (lastToken != token) {
      lastToken = token;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final api = context.read<AppController>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      List<Map<String, dynamic>> next;
      if (api.isLoggedIn) {
        next = await api.loadFollowingVideos(limit: 24);
      } else {
        try {
          next = listResults(await api.callApi('fetchVideos', query: {'limit': 24, 'page': 0, 'sort': 'trending'}));
        } catch (_) {
          next = listResults(await api.callApi('fetchVideos', query: {'limit': 24, 'page': 0, 'sort': 'views'}));
        }
      }
      if (!mounted) return;
      setState(() {
        feed = next;
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
    final title = api.isLoggedIn ? '关注动态' : '趋势视频';
    final empty = api.isLoggedIn ? '暂无关注动态：可能还没关注创作者，或关注列表暂时不可用' : '暂无趋势视频';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('IP ${api.activeIp}', style: const TextStyle(fontSize: 12))),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(children: const [SizedBox(height: 160), Center(child: CircularProgressIndicator())])
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null) ...[
                    Text(error!, style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    api.isLoggedIn ? '来自你关注的创作者' : '未登录：展示全站趋势',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 12),
                  if (feed.isEmpty) Text(empty),
                  ...feed.map(
                    (video) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VideoCard(
                        title: '${video['title'] ?? '未命名'}',
                        subtitle: '${formatCount(video['numViews'])} 播放 · ${formatCount(video['numLikes'])} 喜欢',
                        thumbnailUrl: api.thumbnailUrl(video),
                        onTap: () => Navigator.of(context).pushNamed('/video/${video['id']}'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

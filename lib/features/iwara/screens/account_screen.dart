import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_controller.dart';
import 'package:signal_desk/core/update/update_service.dart';
import 'package:signal_desk/core/update/update_ui.dart';
import '../utils/helpers.dart';
import '../widgets/video_card.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.profileId});
  final String? profileId;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with TickerProviderStateMixin {
  final tokenController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final usernameController = TextEditingController();
  late final TabController authTabs;
  late final TabController contentTabs;
  bool loading = true;
  bool busy = false;
  bool followBusy = false;
  bool edgeBusy = false;
  bool updateBusy = false;
  String currentAppVersion = '';
  final UpdateService updateService = UpdateService();
  String? error;
  Map<String, dynamic>? profile;
  Map<String, dynamic>? currentUser;
  List<Map<String, dynamic>> videos = const [];
  List<Map<String, dynamic>> following = const [];
  bool showAdvancedToken = false;
  EdgeStatus? edgeStatus;
  String? loadedProfileId;
  int videoPage = 0;
  bool videosHasMore = false;
  bool loadingMoreVideos = false;
  static const videoPageSize = 12;

  bool get viewingOther => widget.profileId != null && widget.profileId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    authTabs = TabController(length: 2, vsync: this);
    contentTabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = context.read<AppController>();
      tokenController.text = api.token;
      _load();
      _refreshEdge(silent: true);
    });
  }

  @override
  void dispose() {
    tokenController.dispose();
    emailController.dispose();
    passwordController.dispose();
    usernameController.dispose();
    authTabs.dispose();
    contentTabs.dispose();
    super.dispose();
  }

  Future<void> _refreshEdge({bool silent = false}) async {
    final api = context.read<AppController>();
    try {
      final status = await api.fetchEdgeStatus();
      if (!mounted) return;
      setState(() => edgeStatus = status);
    } catch (e) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('读取节点状态失败: $e')));
    }
  }

  Future<void> _runEdgeTest() async {
    final api = context.read<AppController>();
    setState(() => edgeBusy = true);
    try {
      await api.refreshEdge();
      await _refreshEdge();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('测速完成')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('测速失败: $e')));
    } finally {
      if (mounted) setState(() => edgeBusy = false);
    }
  }

  Future<void> _selectEdge(String ip) async {
    final api = context.read<AppController>();
    setState(() => edgeBusy = true);
    try {
      await api.selectEdgeIp(ip);
      await _refreshEdge();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换 IP: $ip')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('切换失败: $e')));
    } finally {
      if (mounted) setState(() => edgeBusy = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchProfileVideos(String profileId, int page) async {
    final api = context.read<AppController>();
    // Match web account page: prefer /user/{id}/content/videos, fallback to /videos?user=
    try {
      final payload = await api.callApi(
        'fetchUserContent',
        args: {'t': profileId, 'n': 'videos'},
        query: {'limit': videoPageSize, 'page': page},
      );
      final items = listVideos(payload);
      if (items.isNotEmpty || page > 0) return items;
    } catch (_) {
      // fall through
    }
    final payload = await api.callApi(
      'fetchVideos',
      query: {'user': profileId, 'limit': videoPageSize, 'page': page, 'sort': 'date'},
      tokenOverride: '',
    );
    return listVideos(payload);
  }

  Future<void> _loadMoreVideos() async {
    final profileId = (loadedProfileId ?? '').trim();
    if (profileId.isEmpty || loadingMoreVideos || !videosHasMore) return;
    setState(() => loadingMoreVideos = true);
    try {
      final batch = await _fetchProfileVideos(profileId, videoPage);
      if (!mounted) return;
      final merged = <Map<String, dynamic>>[...videos];
      final seen = <String>{for (final item in merged) '${item['id'] ?? item['slug']}'};
      for (final item in batch) {
        final id = '${item['id'] ?? item['slug']}';
        if (seen.add(id)) merged.add(item);
      }
      setState(() {
        videos = merged;
        videoPage += 1;
        videosHasMore = batch.length >= videoPageSize;
        loadingMoreVideos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loadingMoreVideos = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载更多视频失败: $e')));
    }
  }

  Future<void> _load() async {
    final api = context.read<AppController>();
    setState(() {
      loading = true;
      error = null;
      videos = const [];
      videoPage = 0;
      videosHasMore = false;
      loadedProfileId = null;
    });
    try {
      Map<String, dynamic>? nextProfile;
      Map<String, dynamic>? nextCurrent;
      List<Map<String, dynamic>> nextVideos = const [];
      List<Map<String, dynamic>> nextFollowing = const [];
      String? nextProfileId;
      var nextVideoPage = 0;
      var nextVideosHasMore = false;

      if (api.token.isNotEmpty) {
        try {
          await api.resolveAccessToken(force: true);
          nextCurrent = await api.fetchCurrentProfile();
        } catch (_) {
          nextCurrent = null;
        }
      }

      final handle = widget.profileId;
      if (handle != null && handle.isNotEmpty) {
        nextProfile = await api.fetchProfileByHandle(handle);
        nextProfileId = '${nextProfile?['id'] ?? handle}'.trim();
        try {
          nextVideos = await _fetchProfileVideos(nextProfileId, 0);
          nextVideoPage = 1;
          nextVideosHasMore = nextVideos.length >= videoPageSize;
        } catch (_) {
          nextVideos = const [];
        }
        try {
          nextFollowing = await api.fetchFollowingPeople(userId: nextProfileId, limit: 40, maxPages: 2);
        } catch (_) {
          nextFollowing = const [];
        }
      } else if (api.token.isNotEmpty) {
        nextProfile = nextCurrent;
        nextProfileId = '${nextProfile?['id'] ?? ''}'.trim();
        if (nextProfileId.isEmpty) {
          throw Exception('当前用户资料缺少 id，请重新登录或粘贴有效 token');
        }
        try {
          nextVideos = await _fetchProfileVideos(nextProfileId, 0);
          nextVideoPage = 1;
          nextVideosHasMore = nextVideos.length >= videoPageSize;
        } catch (_) {
          nextVideos = const [];
        }
        try {
          nextFollowing = await api.fetchFollowingPeople(userId: nextProfileId, limit: 50, maxPages: 4);
        } catch (e) {
          error = '关注列表: $e';
          nextFollowing = const [];
        }
      }

      if (!mounted) return;
      setState(() {
        profile = nextProfile;
        currentUser = nextCurrent;
        videos = nextVideos;
        following = nextFollowing;
        loadedProfileId = nextProfileId;
        videoPage = nextVideoPage;
        videosHasMore = nextVideosHasMore;
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

  String _tokenFromPayload(dynamic payload) {
    if (payload is! Map) return '';
    final record = Map<String, dynamic>.from(payload);
    final nested = record['data'] is Map ? Map<String, dynamic>.from(record['data'] as Map) : const <String, dynamic>{};
    for (final candidate in [record['token'], record['accessToken'], nested['token'], nested['accessToken']]) {
      final value = '${candidate ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> _submitAuth({required bool register}) async {
    final api = context.read<AppController>();
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写邮箱和密码')));
      return;
    }
    setState(() => busy = true);
    try {
      final payload = await api.callApi(
        register ? 'registerAccount' : 'login',
        body: {
          'email': email,
          'password': password,
          if (register && usernameController.text.trim().isNotEmpty) 'username': usernameController.text.trim(),
          'locale': 'zh-CN',
        },
        tokenOverride: '',
      );
      final token = _tokenFromPayload(payload);
      if (token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(register ? '注册请求已提交，但未返回令牌。' : '登录响应未包含令牌。')),
        );
        return;
      }
      tokenController.text = token;
      await api.setToken(token);
      await api.resolveAccessToken(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(register ? '账号已创建并登录' : '登录成功')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final api = context.read<AppController>();
    final email = emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先填写邮箱地址')));
      return;
    }
    setState(() => busy = true);
    try {
      await api.callApi('forgotPassword', body: {'email': email}, tokenOverride: '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('重置邮件请求已发送（若账号存在）')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveToken() async {
    final api = context.read<AppController>();
    await api.setToken(tokenController.text.trim());
    await api.resolveAccessToken(force: true);
    await _load();
  }

  Future<void> _toggleFollow() async {
    final api = context.read<AppController>();
    if (!api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    final shown = profile == null ? null : unwrapUser(profile);
    final userId = '${shown?['id'] ?? ''}'.trim();
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取用户 id')));
      return;
    }
    final currently = shown?['followedBy'] == true || shown?['following'] == true;
    setState(() => followBusy = true);
    try {
      await api.toggleFollow(userId: userId, currentlyFollowed: currently);
      if (!mounted) return;
      setState(() {
        profile = {
          ...?profile,
          'followedBy': !currently,
          'following': !currently,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(currently ? '已取消关注' : '已关注')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('关注失败: $e')));
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  String _initial(String value) {
    final text = value.trim();
    if (text.isEmpty) return '?';
    return text.characters.first.toUpperCase();
  }


  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => currentAppVersion = info.version);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _checkUpdate({bool quiet = false}) async {
    setState(() => updateBusy = true);
    try {
      final result = await updateService.checkForUpdate();
      if (!mounted) return;
      await presentUpdateCheck(
        context,
        service: updateService,
        result: result,
        quietIfNoUpdate: quiet,
      );
    } finally {
      if (mounted) setState(() => updateBusy = false);
    }
  }

  Widget _updateCard(AppController api) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('应用更新', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '通过 GitHub Releases 检查新版本。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '当前版本: ${currentAppVersion.isEmpty ? '…' : currentAppVersion}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: updateBusy ? null : () => _checkUpdate(),
                    child: Text(updateBusy ? '检查中…' : '检查更新'),
                  ),
                  if (api.onExitModule != null)
                    OutlinedButton(
                      onPressed: api.onExitModule,
                      child: const Text('退出项目'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _edgeCard(AppController api) {
    final status = edgeStatus;
    final results = status?.results ?? const <EdgeProbeResult>[];
    final selected = status?.selectedIp ?? status?.activeIp ?? api.activeIp;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('网络节点 / 强制 IP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '仅首次启动自动测速。这里可手动测速并切换强制解析 IP。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('当前 IP: ${api.activeIp}', style: const TextStyle(fontFamily: 'monospace')),
            Text('状态: ${status?.status ?? '-'} · 模式: ${status?.selectionMode ?? '-'}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: edgeBusy ? null : _runEdgeTest,
                  child: Text(edgeBusy ? '测速中…' : '重新测速'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: edgeBusy ? null : () => _refreshEdge(),
                  child: const Text('刷新状态'),
                ),
              ],
            ),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('可选节点', style: TextStyle(fontWeight: FontWeight.w600)),
              ...results.take(8).map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.ip, style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text('${item.latencyMs.toStringAsFixed(1)} ms'),
                      trailing: selected == item.ip
                          ? const Icon(Icons.check, color: Colors.greenAccent)
                          : const Text('使用'),
                      selected: selected == item.ip,
                      onTap: edgeBusy ? null : () => _selectEdge(item.ip),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<AppController>();
    final shown = profile == null ? null : unwrapUser(profile);
    final currentId = '${currentUser?['id'] ?? ''}'.trim();
    final shownId = '${shown?['id'] ?? ''}'.trim();
    final isSelf = !viewingOther || (currentId.isNotEmpty && shownId.isNotEmpty && currentId == shownId);
    final followed = shown?['followedBy'] == true || shown?['following'] == true;

    return Scaffold(
      appBar: AppBar(title: Text(viewingOther ? '用户主页' : '账户')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
                if (!viewingOther) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('账号登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            '邮箱密码登录会通过本地强制 IP 代理访问 api.iwara.tv，令牌只保存在本机。',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          TabBar(
                            controller: authTabs,
                            tabs: const [
                              Tab(text: '登录'),
                              Tab(text: '注册'),
                            ],
                          ),
                          SizedBox(
                            height: 250,
                            child: TabBarView(
                              controller: authTabs,
                              children: [
                                ListView(
                                  children: [
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(labelText: '邮箱', hintText: 'you@example.com'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: passwordController,
                                      obscureText: true,
                                      decoration: const InputDecoration(labelText: '密码'),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed: busy ? null : () => _submitAuth(register: false),
                                      child: Text(busy ? '处理中…' : '登录'),
                                    ),
                                    TextButton(
                                      onPressed: busy ? null : _forgotPassword,
                                      child: const Text('忘记密码？发送重置邮件'),
                                    ),
                                  ],
                                ),
                                ListView(
                                  children: [
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: usernameController,
                                      decoration: const InputDecoration(labelText: '用户名（可选）'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(labelText: '邮箱'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: passwordController,
                                      obscureText: true,
                                      decoration: const InputDecoration(labelText: '密码（至少 8 位）'),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed: busy ? null : () => _submitAuth(register: true),
                                      child: Text(busy ? '处理中…' : '创建账号'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => showAdvancedToken = !showAdvancedToken),
                            icon: Icon(showAdvancedToken ? Icons.expand_less : Icons.expand_more),
                            label: Text(showAdvancedToken ? '收起高级选项' : '高级：手动粘贴 Token'),
                          ),
                          if (showAdvancedToken) ...[
                            TextField(
                              controller: tokenController,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(hintText: '粘贴 access token 或可交换凭证'),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.tonal(onPressed: _saveToken, child: const Text('保存并刷新')),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () async {
                                    tokenController.clear();
                                    await api.setToken('');
                                    await _load();
                                  },
                                  child: const Text('退出登录'),
                                ),
                              ],
                            ),
                          ] else if (api.token.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            OutlinedButton(
                              onPressed: () async {
                                tokenController.clear();
                                await api.setToken('');
                                await _load();
                              },
                              child: const Text('退出登录'),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text('本地代理: ${api.baseUrl}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _edgeCard(api),
                  const SizedBox(height: 12),
                  _updateCard(api),
                  const SizedBox(height: 16),
                ],
                if (shown == null || shown.isEmpty)
                  const Card(child: ListTile(title: Text('未登录'), subtitle: Text('登录后显示当前用户资料')))
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(child: Text(_initial(displayName(shown)))),
                            title: Text(displayName(shown)),
                            subtitle: Text(
                              '@${shown['username'] ?? shown['id'] ?? ''}\n关注 ${formatCount(shown['numFollowing'] ?? following.length)} · 粉丝 ${formatCount(shown['numFollowers'])}',
                            ),
                            isThreeLine: true,
                          ),
                          if (viewingOther && !isSelf)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton(
                                onPressed: followBusy ? null : _toggleFollow,
                                child: Text(followBusy ? '处理中…' : (followed ? '取消关注' : '关注')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TabBar(
                  controller: contentTabs,
                  tabs: [
                    Tab(text: '视频 ${videos.length}'),
                    Tab(text: '关注 ${following.length}'),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: contentTabs,
                  builder: (context, _) {
                    if (contentTabs.index == 1) {
                      if (following.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('暂无关注的人（或关注列表不可用）'),
                        );
                      }
                      return Column(
                        children: [
                          for (final person in following)
                            Card(
                              child: ListTile(
                                leading: CircleAvatar(child: Text(_initial(displayName(person)))),
                                title: Text(displayName(person)),
                                subtitle: Text('@${person['username'] ?? person['id'] ?? ''}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  final username = '${person['username'] ?? person['id'] ?? ''}'.trim();
                                  if (username.isEmpty) return;
                                  Navigator.of(context).pushNamed('/account/$username');
                                },
                              ),
                            ),
                        ],
                      );
                    }
                    if (videos.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('暂无视频'),
                      );
                    }
                    return Column(
                      children: [
                        for (final item in videos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: VideoCard(
                              title: '${item['title'] ?? '未命名'}',
                              subtitle: '${formatCount(item['numViews'])} 播放 · ${formatCount(item['numLikes'])} 点赞',
                              thumbnailUrl: api.thumbnailUrl(item),
                              onTap: () => Navigator.of(context).pushNamed('/video/${item['id']}'),
                            ),
                          ),
                        if (videosHasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: FilledButton.tonal(
                                onPressed: loadingMoreVideos ? null : _loadMoreVideos,
                                child: Text(loadingMoreVideos ? '加载中…' : '加载更多视频'),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }
}

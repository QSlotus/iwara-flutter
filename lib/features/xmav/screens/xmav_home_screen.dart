import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/xmav_controller.dart';
import '../widgets/xmav_video_card.dart';
import 'xmav_detail_screen.dart';

class XmavHomeScreen extends StatefulWidget {
  const XmavHomeScreen({super.key});

  @override
  State<XmavHomeScreen> createState() => _XmavHomeScreenState();
}

class _XmavHomeScreenState extends State<XmavHomeScreen> {
  int tab = 0;
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<XmavController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(tab == 0 ? 'Xmav · 最新' : tab == 1 ? 'Xmav · 分类' : 'Xmav · 搜索'),
        leading: IconButton(
          tooltip: '退出模块',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => api.onExitModule?.call(),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'refresh_base') {
                await api.refreshBase(force: true);
                if (context.mounted && api.ready) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('线路已刷新: ${api.base}')),
                  );
                }
              } else if (value == 'reload') {
                if (tab == 0) await api.loadLatest(page: api.latestPage);
                if (tab == 1 && api.selectedTid != null) {
                  await api.loadCategory(api.selectedTid!, page: api.categoryPage);
                }
                if (tab == 2 && api.searchKeyword.isNotEmpty) {
                  await api.runSearch(api.searchKeyword, page: api.searchPage);
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'refresh_base', child: Text('刷新线路')),
              PopupMenuItem(value: 'reload', child: Text('重新加载当前页')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: [
          _LatestTab(onOpen: _openDetail),
          _CategoryTab(onOpen: _openDetail),
          _SearchTab(
            controller: searchController,
            onOpen: _openDetail,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fiber_new_outlined), label: '最新'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: '分类'),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
        ],
      ),
    );
  }

  void _openDetail(XmavVideoItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => XmavDetailScreen(item: item)),
    );
  }
}

class _LatestTab extends StatelessWidget {
  const _LatestTab({required this.onOpen});
  final ValueChanged<XmavVideoItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final api = context.watch<XmavController>();
    if (api.latestLoading && api.latestItems.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (api.lastError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(api.lastError!, style: const TextStyle(color: Colors.redAccent)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => api.loadLatest(page: 1),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: api.latestItems.length,
              itemBuilder: (context, index) {
                final item = api.latestItems[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: XmavVideoCard(
                    title: item.title.isEmpty ? '未命名' : item.title,
                    subtitle: _subtitle(item),
                    thumbnailUrl: item.cover,
                    badge: item.remarks.isNotEmpty ? item.remarks : item.vodClass,
                    onTap: () => onOpen(item),
                  ),
                );
              },
            ),
          ),
        ),
        XmavPager(
          page: api.latestPage,
          pageCount: api.latestPageCount,
          busy: api.latestLoading,
          onPage: (p) => api.loadLatest(page: p),
        ),
      ],
    );
  }
}


class _CategoryTab extends StatelessWidget {
  const _CategoryTab({required this.onOpen});
  final ValueChanged<XmavVideoItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final api = context.watch<XmavController>();
    if (api.selectedTid == null) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
        ),
        itemCount: api.categories.length,
        itemBuilder: (context, index) {
          final cat = api.categories[index];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => api.openCategory(cat),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    cat.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        ListTile(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: api.clearCategorySelection,
          ),
          title: Text(api.selectedCategoryName.isEmpty ? '分类' : api.selectedCategoryName),
          subtitle: Text('tid=${api.selectedTid}'),
        ),
        if (api.categoryLoading && api.categoryItems.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => api.loadCategory(api.selectedTid!, page: 1),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: api.categoryItems.length,
                itemBuilder: (context, index) {
                  final item = api.categoryItems[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: XmavVideoCard(
                      title: item.title.isEmpty ? '未命名' : item.title,
                      subtitle: _subtitle(item),
                      thumbnailUrl: item.cover,
                      badge: item.remarks.isNotEmpty ? item.remarks : item.vodClass,
                      onTap: () => onOpen(item),
                    ),
                  );
                },
              ),
            ),
          ),
        XmavPager(
          page: api.categoryPage,
          pageCount: api.categoryPageCount,
          busy: api.categoryLoading,
          onPage: (p) => api.loadCategory(api.selectedTid!, page: p),
        ),
      ],
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab({required this.controller, required this.onOpen});

  final TextEditingController controller;
  final ValueChanged<XmavVideoItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final api = context.watch<XmavController>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '搜索关键词',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) {
                      api.loadSuggestions(v);
                    }
                  },
                  onSubmitted: (v) => api.runSearch(v, page: 1),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => api.runSearch(controller.text, page: 1),
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        if (api.suggestions.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: api.suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final s = api.suggestions[index];
                return ActionChip(
                  label: Text(s.name, overflow: TextOverflow.ellipsis),
                  onPressed: () {
                    controller.text = s.name;
                    if (s.id > 0) {
                      onOpen(XmavVideoItem(id: s.id, title: s.name, cover: s.pic));
                    } else {
                      api.runSearch(s.name, page: 1);
                    }
                  },
                );
              },
            ),
          ),
        if (api.searchLoading && api.searchItems.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: api.searchItems.isEmpty
                ? Center(
                    child: Text(
                      api.searchKeyword.isEmpty ? '输入关键词开始搜索' : '无结果',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: api.searchItems.length,
                    itemBuilder: (context, index) {
                      final item = api.searchItems[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: XmavVideoCard(
                          title: item.title.isEmpty ? '未命名' : item.title,
                          subtitle: _subtitle(item),
                          thumbnailUrl: item.cover,
                          badge: item.vodClass,
                          onTap: () => onOpen(item),
                        ),
                      );
                    },
                  ),
          ),
        if (api.searchKeyword.isNotEmpty)
          XmavPager(
            page: api.searchPage,
            pageCount: api.searchPageCount,
            busy: api.searchLoading,
            onPage: (p) => api.runSearch(api.searchKeyword, page: p),
          ),
      ],
    );
  }
}

String _subtitle(XmavVideoItem item) {
  final parts = <String>[];
  if (item.vodClass.isNotEmpty) parts.add(item.vodClass);
  if (item.hits > 0) parts.add('热度 ${item.hits}');
  if (item.time.isNotEmpty) parts.add(item.time);
  if (parts.isEmpty && item.blurb.isNotEmpty) return item.blurb;
  return parts.join(' · ');
}

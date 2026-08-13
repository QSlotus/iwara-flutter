import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'qinav_http.dart';
import 'qinav_server.dart';
import 'qinav_site.dart';

enum QinavFeed { latest, hot, like, rank, category, search }

class QinavController extends ChangeNotifier {
  QinavController({required String resolveIp, this.onExitModule}) {
    http = QinavHttp(resolveIp: resolveIp);
    site = QinavSite(http);
    server = QinavServer(site: site, http: http);
  }

  late final QinavHttp http;
  late final QinavSite site;
  late final QinavServer server;
  final VoidCallback? onExitModule;

  bool ready = false;
  String? lastError;

  QinavFeed feed = QinavFeed.latest;
  int categoryId = 1;
  int page = 1;
  bool loading = false;
  bool loadingMore = false;
  String searchKeyword = '';
  List<QinavVideoItem> items = const [];
  List<QinavTag> tags = const [];

  String get baseUrl => server.baseUrl;
  String get activeIp => http.resolveIp;

  Future<void> initialize() async {
    try {
      await server.start();
      ready = true;
      notifyListeners();
      await Future.wait([
        refreshFeed(),
        _loadTags(),
      ]);
    } catch (e, st) {
      lastError = '$e\n$st';
      ready = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _loadTags() async {
    try {
      tags = await site.tags();
      notifyListeners();
    } catch (_) {
      // optional
    }
  }

  Future<void> refreshFeed() async {
    loading = true;
    lastError = null;
    page = 1;
    notifyListeners();
    try {
      items = await _loadPage(1);
    } catch (e) {
      lastError = '$e';
      items = const [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final next = page + 1;
      final more = await _loadPage(next);
      if (more.isNotEmpty) {
        page = next;
        items = [...items, ...more];
      }
    } catch (e) {
      lastError = '$e';
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  Future<List<QinavVideoItem>> _loadPage(int page) {
    switch (feed) {
      case QinavFeed.latest:
        return site.listNew(page);
      case QinavFeed.hot:
        return site.listHot(page);
      case QinavFeed.like:
        return site.listLike(page);
      case QinavFeed.rank:
        return page <= 1 ? site.rank() : Future.value(const []);
      case QinavFeed.category:
        return site.listSite(categoryId, page);
      case QinavFeed.search:
        return site.search(searchKeyword, page).then((r) => r.items);
    }
  }

  Future<void> setFeed(QinavFeed next, {int? cid, String? keyword}) async {
    feed = next;
    if (cid != null) categoryId = cid;
    if (keyword != null) searchKeyword = keyword.trim();
    await refreshFeed();
  }

  Future<QinavVideoDetail> fetchDetail(int vid) => site.videoDetail(vid);

  Future<QinavPlayback> fetchPlayback(int vid) => site.playback(vid);

  String proxiedMaster(String masterUrl) {
    return '$baseUrl/api/hls/master?url=${Uri.encodeQueryComponent(masterUrl)}';
  }

  String proxiedImage(String url) {
    final value = url.trim();
    if (value.isEmpty) return '';
    final abs = value.startsWith('http') ? value : 'https:$value';
    return '$baseUrl/api/img?url=${Uri.encodeQueryComponent(abs)}';
  }

  Future<void> disposeModule() async {
    try {
      await server.stop();
    } catch (_) {}
    ready = false;
  }
}

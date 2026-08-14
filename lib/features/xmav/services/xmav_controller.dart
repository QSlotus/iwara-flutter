import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'xmav_api.dart';
import 'xmav_base.dart';
import 'xmav_http.dart';
import 'xmav_server.dart';

class XmavController extends ChangeNotifier {
  XmavController({this.onExitModule});

  final VoidCallback? onExitModule;

  final XmavHttp http = XmavHttp();
  SharedPreferences? _prefs;
  XmavBaseStore? _store;
  XmavBaseResolver? _resolver;
  XmavApi? api;
  XmavServer? server;

  bool ready = false;
  bool resolvingBase = false;
  String? lastError;
  String base = '';

  List<XmavCategory> categories = List<XmavCategory>.from(xmavFallbackCategories);

  bool latestLoading = false;
  List<XmavVideoItem> latestItems = const [];
  int latestPage = 1;
  int latestPageCount = 1;

  int? selectedTid;
  String selectedCategoryName = '';
  bool categoryLoading = false;
  List<XmavVideoItem> categoryItems = const [];
  int categoryPage = 1;
  int categoryPageCount = 1;

  String searchKeyword = '';
  bool searchLoading = false;
  List<XmavVideoItem> searchItems = const [];
  List<XmavSuggestItem> suggestions = const [];
  int searchPage = 1;
  int searchPageCount = 1;

  Future<void> initialize() async {
    resolvingBase = true;
    lastError = null;
    ready = false;
    notifyListeners();
    try {
      _prefs = await SharedPreferences.getInstance();
      _store = XmavBaseStore(_prefs!);
      _resolver = XmavBaseResolver(http: http, store: _store!);
      base = await _resolver!.resolve(force: false);
      api = XmavApi(http: http, base: base);
      server = XmavServer(http: http, siteBase: base);
      await server!.start();
      categories = await api!.loadCategories();
      ready = true;
      resolvingBase = false;
      notifyListeners();
      await loadLatest(page: 1);
    } catch (e) {
      lastError = '$e';
      ready = false;
      resolvingBase = false;
      notifyListeners();
    }
  }

  Future<void> refreshBase({bool force = true}) async {
    if (_resolver == null) {
      await initialize();
      return;
    }
    resolvingBase = true;
    lastError = null;
    notifyListeners();
    try {
      base = await _resolver!.resolve(force: force);
      api = XmavApi(http: http, base: base);
      if (server != null) {
        server!.siteBase = base;
      } else {
        server = XmavServer(http: http, siteBase: base);
        await server!.start();
      }
      categories = await api!.loadCategories();
      ready = true;
      resolvingBase = false;
      notifyListeners();
      await loadLatest(page: 1);
      if (selectedTid != null) {
        await loadCategory(selectedTid!, page: 1);
      }
      if (searchKeyword.isNotEmpty) {
        await runSearch(searchKeyword, page: 1);
      }
    } catch (e) {
      lastError = '$e';
      ready = false;
      resolvingBase = false;
      notifyListeners();
    }
  }

  Future<void> loadLatest({int page = 1}) async {
    if (api == null) return;
    latestLoading = true;
    lastError = null;
    notifyListeners();
    try {
      final result = await api!.list(page: page, limit: 20);
      latestItems = result.items;
      latestPage = result.page;
      latestPageCount = result.pageCount < 1 ? 1 : result.pageCount;
    } catch (e) {
      lastError = '$e';
      latestItems = const [];
    } finally {
      latestLoading = false;
      notifyListeners();
    }
  }

  void clearCategorySelection() {
    selectedTid = null;
    selectedCategoryName = '';
    categoryItems = const [];
    categoryPage = 1;
    categoryPageCount = 1;
    notifyListeners();
  }

  Future<void> openCategory(XmavCategory cat) async {
    selectedTid = cat.tid;
    selectedCategoryName = cat.name;
    categoryItems = const [];
    notifyListeners();
    await loadCategory(cat.tid, page: 1);
  }

  Future<void> loadCategory(int tid, {int page = 1}) async {
    if (api == null) return;
    categoryLoading = true;
    lastError = null;
    notifyListeners();
    try {
      final result = await api!.list(
        page: page,
        limit: 40,
        tid: tid,
        strictTypeId: tid,
        fillPages: 4,
      );
      categoryItems = result.items;
      categoryPage = result.page;
      categoryPageCount = result.pageCount < 1 ? 1 : result.pageCount;
    } catch (e) {
      lastError = '$e';
      categoryItems = const [];
    } finally {
      categoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSuggestions(String keyword) async {
    if (api == null) return;
    final wd = keyword.trim();
    if (wd.isEmpty) {
      suggestions = const [];
      notifyListeners();
      return;
    }
    try {
      suggestions = await api!.suggest(wd);
    } catch (_) {
      suggestions = const [];
    }
    notifyListeners();
  }

  Future<void> runSearch(String keyword, {int page = 1}) async {
    if (api == null) return;
    final wd = keyword.trim();
    searchKeyword = wd;
    if (wd.isEmpty) {
      searchItems = const [];
      searchPage = 1;
      searchPageCount = 1;
      notifyListeners();
      return;
    }
    searchLoading = true;
    lastError = null;
    suggestions = const [];
    notifyListeners();
    try {
      final result = await api!.searchHtml(wd, page: page);
      searchItems = result.items;
      searchPage = result.page;
      searchPageCount = result.pageCount < 1 ? 1 : result.pageCount;
    } catch (e) {
      lastError = '$e';
      searchItems = const [];
    } finally {
      searchLoading = false;
      notifyListeners();
    }
  }

  Future<XmavPlayback> fetchPlayback(int vodId) {
    if (api == null) throw StateError('Xmav not ready');
    return api!.resolvePlayback(vodId, sid: 1, nid: 1);
  }

  String proxiedPlay(String upstreamUrl) {
    final s = server;
    if (s == null) return upstreamUrl;
    return s.resolvePlayableProxyUrl(upstreamUrl);
  }

  Future<void> disposeModule() async {
    try {
      await server?.stop();
    } catch (_) {}
    server = null;
    try {
      http.close();
    } catch (_) {}
    ready = false;
    api = null;
  }
}
import 'dart:convert';

import '../models/models.dart';
import 'qinav_cdn.dart';
import 'qinav_http.dart';
import 'qinav_parser.dart';

class QinavSite {
  QinavSite(this.http) : cdn = QinavCdnResolver(http);

  final QinavHttp http;
  final QinavCdnResolver cdn;

  Future<List<QinavVideoItem>> list(String path) async {
    return parseVideoItems(await http.getText('${QinavHttp.base}$path'));
  }

  Future<List<QinavVideoItem>> listNew([int page = 1]) {
    return list(page <= 1 ? '/new.html' : '/new-$page.html');
  }

  Future<List<QinavVideoItem>> listHot([int page = 1]) {
    return list(page <= 1 ? '/hot.html' : '/hot-$page.html');
  }

  Future<List<QinavVideoItem>> listLike([int page = 1]) {
    return list(page <= 1 ? '/like.html' : '/like-$page.html');
  }

  Future<List<QinavVideoItem>> listSite(int cid, [int page = 1]) {
    return list(page <= 1 ? '/site/5/$cid.html' : '/site/5/$cid-$page.html');
  }

  Future<List<QinavVideoItem>> rank() => list('/rank/index.html');

  Future<List<QinavTag>> tags() async {
    return parseTagCloud(await http.getText('${QinavHttp.base}/tags/1.html'));
  }

  Future<QinavSearchResult> search(String keyword, [int page = 1]) async {
    final r = await http.postForm(
      '${QinavHttp.base}/?module=tags&action=keyword',
      'keyword=${Uri.encodeQueryComponent(keyword)}',
    );
    var finalPath = Uri.parse(r.finalUrl).path;
    if (finalPath.isEmpty) finalPath = '/';
    final m = RegExp(r'^/tags/(\d+)(?:-(\d+))?\.html$').firstMatch(finalPath);
    if (m != null && page > 1 && m.group(2) == null) {
      finalPath = '/tags/${m.group(1)}-$page.html';
      final html = await http.getText('${QinavHttp.base}$finalPath');
      return parseSearch(html, keyword, page, finalPath);
    }
    final html = utf8.decode(r.body, allowMalformed: true);
    return parseSearch(html, keyword, page, finalPath);
  }

  Future<QinavVideoDetail> videoDetail(int vid) async {
    return parseVideoDetail(await http.getText('${QinavHttp.base}/video/$vid.html'));
  }

  Future<QinavPlayback> playback(int vid) async {
    final embed = await http.getText('${QinavHttp.base}/embed/$vid.html');
    final m3u8 = parseEmbedM3u8(embed);
    cdn.addDomain(Uri.parse(m3u8).host);
    final resolved = await cdn.resolvePlayable(m3u8);
    if (resolved != null) {
      final variants = await masterVariants(resolved);
      return QinavPlayback(url: resolved, reachable: true, variants: variants);
    }
    return QinavPlayback(url: m3u8, reachable: false);
  }

  Future<List<QinavVariant>> masterVariants(String masterUrl) async {
    try {
      final text = await http.getText(masterUrl);
      return parseMaster(text, masterUrl);
    } catch (_) {
      return const [];
    }
  }
}

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

final _videoRe = RegExp(r'^/video/(\d+)\.html$');
final _tagRe = RegExp(r'^/tags/(\d+)');
final _embedUrlRe = RegExp(r'''const\s+url\s*=\s*['\"]([^'\"]+)['\"]''');
final _totalRe = RegExp(r'(\d+)\s*个视频');

int _toInt(String? text) {
  final digits = RegExp(r'\d+').allMatches(text ?? '').map((m) => m.group(0)!).join();
  return int.tryParse(digits) ?? 0;
}

List<QinavVideoItem> parseVideoItems(String html) {
  final doc = html_parser.parse(html);
  final items = <QinavVideoItem>[];
  for (final a in doc.querySelectorAll("a[href^='/video/']")) {
    final href = a.attributes['href'] ?? '';
    final m = _videoRe.firstMatch(href);
    if (m == null) continue;
    Element? ul = a.parent;
    while (ul != null && ul.localName != 'ul') {
      ul = ul.parent;
    }
    if (ul == null) continue;

    final img = ul.querySelector('li.image img');
    final note = ul.querySelector('li.image span.note');
    final view = ul.querySelector('li.view');
    final us = view?.querySelectorAll('u') ?? const <Element>[];
    final sp = view?.querySelector('span');

    items.add(QinavVideoItem(
      vid: int.parse(m.group(1)!),
      title: ul.querySelector('li.title')?.text.trim() ?? '',
      url: href,
      cover: (img?.attributes['img'] ?? img?.attributes['src'] ?? '').trim(),
      duration: note?.text.trim() ?? '',
      views: us.isNotEmpty ? _toInt(us[0].text) : 0,
      likes: us.length > 1 ? _toInt(us[1].text) : 0,
      time: sp?.text.trim() ?? '',
    ));
  }
  return items;
}

QinavVideoDetail parseVideoDetail(String html) {
  final doc = html_parser.parse(html);
  final iframe = doc.querySelector('div.player iframe')?.attributes['src'] ?? '';
  final logs = doc.querySelector('div.logs');

  var vid = 0;
  final vidAttr = logs?.attributes['vid'];
  if (vidAttr != null && vidAttr.isNotEmpty) {
    vid = int.tryParse(vidAttr) ?? 0;
  } else {
    final m = RegExp(r'(\d+)').firstMatch(iframe);
    if (m != null) vid = int.tryParse(m.group(1)!) ?? 0;
  }

  var zan = 0, cai = 0, fav = 0;
  for (final el in logs?.querySelectorAll('li') ?? const <Element>[]) {
    final t = (el.attributes['type'] ?? '').trim();
    final n = _toInt(el.text);
    if (t == 'zan') zan = n;
    if (t == 'cai') cai = n;
    if (t == 'like') fav = n;
  }

  return QinavVideoDetail(
    vid: vid,
    title: doc.querySelector('h1')?.text.trim() ?? '',
    description: (doc.querySelector('div.des')?.text.trim() ?? '').replaceFirst(RegExp(r'^简介[：:]'), ''),
    embedUrl: iframe.isNotEmpty ? iframe : '/embed/$vid.html',
    zan: zan,
    cai: cai,
    favorites: fav,
    related: parseVideoItems(html),
  );
}

String parseEmbedM3u8(String embedHtml) {
  final m = _embedUrlRe.firstMatch(embedHtml);
  if (m == null) {
    throw StateError('embed page missing video url (const url)');
  }
  return m.group(1)!;
}

QinavSearchResult parseSearch(String html, String keyword, int page, String finalUrl) {
  final m = _tagRe.firstMatch(finalUrl);
  final tagId = m != null ? int.tryParse(m.group(1)!) : null;
  final doc = html_parser.parse(html);
  final title = doc.querySelector('title')?.text.trim() ?? '';
  final tagName = title.isEmpty ? '' : title.split(RegExp(r'\s+')).first;
  int? total;
  final h1 = doc.querySelector('h1')?.text ?? '';
  final mt = _totalRe.firstMatch(h1);
  if (mt != null) total = int.tryParse(mt.group(1)!);

  return QinavSearchResult(
    keyword: keyword,
    items: parseVideoItems(html),
    total: total,
    tagId: tagId,
    tagName: tagName,
    page: page,
    url: finalUrl,
  );
}

List<QinavTag> parseTagCloud(String html) {
  final doc = html_parser.parse(html);
  final tags = <QinavTag>[];
  for (final a in doc.querySelectorAll("a[href^='/tags/']")) {
    final href = a.attributes['href'] ?? '';
    final m = _tagRe.firstMatch(href);
    if (m == null || href == '/tags/1.html') continue;
    final i = a.querySelector('i');
    final name = a.text.replaceAll(i?.text ?? '', '').trim();
    tags.add(QinavTag(
      tagId: int.parse(m.group(1)!),
      name: name,
      count: i == null ? 0 : _toInt(i.text),
      url: href,
    ));
  }
  return tags;
}

List<QinavVariant> parseMaster(String text, String baseUrl) {
  final base = Uri.parse(baseUrl);
  final variants = <QinavVariant>[];
  var bw = 0;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('#EXT-X-STREAM-INF')) {
      final m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(t);
      bw = m != null ? int.parse(m.group(1)!) : 0;
    } else if (!t.startsWith('#')) {
      variants.add(QinavVariant(bandwidth: bw, url: base.resolve(t).toString()));
    }
  }
  return variants;
}

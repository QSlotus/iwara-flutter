class QinavVideoItem {
  QinavVideoItem({
    required this.vid,
    required this.title,
    this.url = '',
    this.cover = '',
    this.duration = '',
    this.views = 0,
    this.likes = 0,
    this.time = '',
  });

  final int vid;
  final String title;
  final String url;
  final String cover;
  final String duration;
  final int views;
  final int likes;
  final String time;
}

class QinavVideoDetail {
  QinavVideoDetail({
    required this.vid,
    required this.title,
    this.description = '',
    this.embedUrl = '',
    this.zan = 0,
    this.cai = 0,
    this.favorites = 0,
    this.related = const [],
  });

  final int vid;
  final String title;
  final String description;
  final String embedUrl;
  final int zan;
  final int cai;
  final int favorites;
  final List<QinavVideoItem> related;
}

class QinavSearchResult {
  QinavSearchResult({
    required this.keyword,
    required this.items,
    this.total,
    this.tagId,
    this.tagName = '',
    this.page = 1,
    this.url = '',
  });

  final String keyword;
  final List<QinavVideoItem> items;
  final int? total;
  final int? tagId;
  final String tagName;
  final int page;
  final String url;
}

class QinavTag {
  QinavTag({required this.tagId, required this.name, this.count = 0, this.url = ''});
  final int tagId;
  final String name;
  final int count;
  final String url;
}

class QinavPlayback {
  QinavPlayback({required this.url, required this.reachable, this.variants = const []});
  final String url;
  final bool reachable;
  final List<QinavVariant> variants;
}

class QinavVariant {
  QinavVariant({required this.bandwidth, required this.url});
  final int bandwidth;
  final String url;
}

const qinavCategories = <int, String>{
  1: '亚洲情色',
  2: '国产主播',
  3: '国产自拍',
  4: '无码专区',
  5: '欧美性爱',
  6: '熟女人妻',
  7: '强奸乱伦',
  8: '巨乳美乳',
  9: '中文字幕',
  10: '制服诱惑',
  11: '女同性恋',
  12: '卡通动画',
  13: '视频伦理',
  14: '少女萝莉',
  15: '重口色情',
  33: '福利姬',
};


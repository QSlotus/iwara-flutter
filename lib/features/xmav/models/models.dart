class XmavVideoItem {
  XmavVideoItem({
    required this.id,
    required this.title,
    this.cover = '',
    this.blurb = '',
    this.actor = '',
    this.vodClass = '',
    this.remarks = '',
    this.time = '',
    this.hits = 0,
    this.score = '',
    this.typeId = 0,
    this.duration = '',
  });

  final int id;
  final String title;
  final String cover;
  final String blurb;
  final String actor;
  final String vodClass;
  final String remarks;
  final String time;
  final int hits;
  final String score;
  final int typeId;
  final String duration;

  factory XmavVideoItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      return int.tryParse('$v') ?? 0;
    }

    String asStr(dynamic v) => v == null ? '' : '$v'.trim();

    final content = asStr(json['vod_content']);
    final blurb = asStr(json['vod_blurb']);
    return XmavVideoItem(
      id: asInt(json['vod_id'] ?? json['id']),
      title: asStr(json['vod_name'] ?? json['name']),
      cover: asStr(json['vod_pic'] ?? json['pic']),
      blurb: blurb.isNotEmpty ? blurb : content,
      actor: asStr(json['vod_actor']),
      vodClass: asStr(json['vod_class']),
      remarks: asStr(json['vod_remarks']),
      time: asStr(json['vod_time'] ?? json['vod_time_add']),
      hits: asInt(json['vod_hits']),
      score: asStr(json['vod_score']),
      typeId: asInt(json['type_id']),
      duration: asStr(json['vod_duration']),
    );
  }
}

class XmavPageResult {
  XmavPageResult({
    required this.items,
    this.page = 1,
    this.pageCount = 1,
    this.limit = 20,
    this.total = 0,
  });

  final List<XmavVideoItem> items;
  final int page;
  final int pageCount;
  final int limit;
  final int total;
}

class XmavSuggestItem {
  XmavSuggestItem({required this.id, required this.name, this.pic = '', this.en = ''});

  final int id;
  final String name;
  final String pic;
  final String en;

  factory XmavSuggestItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      return int.tryParse('$v') ?? 0;
    }

    return XmavSuggestItem(
      id: asInt(json['id'] ?? json['vod_id']),
      name: '${json['name'] ?? json['vod_name'] ?? ''}'.trim(),
      pic: '${json['pic'] ?? json['vod_pic'] ?? ''}'.trim(),
      en: '${json['en'] ?? json['vod_en'] ?? ''}'.trim(),
    );
  }
}

class XmavCategory {
  const XmavCategory({required this.tid, required this.name});
  final int tid;
  final String name;
}

class XmavPlayback {
  XmavPlayback({
    required this.url,
    this.from = '',
    this.encrypt = 0,
    this.title = '',
    this.usedParse = false,
  });

  final String url;
  final String from;
  final int encrypt;
  final String title;
  final bool usedParse;
}

/// Snapshot categories from docs (2026-08-13). Prefer live home nav when available.
const xmavFallbackCategories = <XmavCategory>[
  XmavCategory(tid: 24, name: '国产自拍'),
  XmavCategory(tid: 34, name: '国产精选'),
  XmavCategory(tid: 29, name: '无码高清'),
  XmavCategory(tid: 25, name: '中文字幕'),
  XmavCategory(tid: 35, name: '国产精品'),
  XmavCategory(tid: 30, name: '真实乱伦'),
  XmavCategory(tid: 38, name: '网曝黑料'),
  XmavCategory(tid: 37, name: '学生妹系'),
  XmavCategory(tid: 22, name: '国产制作'),
  XmavCategory(tid: 40, name: '偷拍自拍'),
  XmavCategory(tid: 41, name: '乱伦系列'),
  XmavCategory(tid: 2, name: '探花约炮'),
  XmavCategory(tid: 21, name: '精东影业'),
  XmavCategory(tid: 31, name: '蜜桃传媒'),
  XmavCategory(tid: 33, name: '果冻传媒'),
  XmavCategory(tid: 36, name: '麻豆传媒'),
  XmavCategory(tid: 39, name: '热门大瓜'),
  XmavCategory(tid: 42, name: '黑料网曝'),
  XmavCategory(tid: 32, name: '中文字幕'),
  XmavCategory(tid: 6, name: '高清无码'),
  XmavCategory(tid: 7, name: '高清有码'),
  XmavCategory(tid: 26, name: '无码流出'),
  XmavCategory(tid: 28, name: '无码视频'),
  XmavCategory(tid: 3, name: '欧美精品'),
  XmavCategory(tid: 4, name: '动漫精选'),
];

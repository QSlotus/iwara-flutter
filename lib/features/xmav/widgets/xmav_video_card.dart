import 'package:flutter/material.dart';

class XmavVideoCard extends StatelessWidget {
  const XmavVideoCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.thumbnailUrl,
    this.badge,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
                    Image.network(
                      thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: Colors.black26,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    )
                  else
                    Container(
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: const Icon(Icons.movie_outlined),
                    ),
                  if ((badge ?? '').isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: Text(badge!, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class XmavPager extends StatelessWidget {
  const XmavPager({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPage,
    this.busy = false,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final total = pageCount < 1 ? 1 : pageCount;
    final cur = page.clamp(1, total);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: busy || cur <= 1 ? null : () => onPage(cur - 1),
            child: const Text('上一页'),
          ),
          Expanded(
            child: Text(
              '$cur / $total',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ),
          OutlinedButton(
            onPressed: busy || cur >= total ? null : () => onPage(cur + 1),
            child: const Text('下一页'),
          ),
        ],
      ),
    );
  }
}

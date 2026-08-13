import 'package:flutter/material.dart';

class QinavVideoCard extends StatelessWidget {
  const QinavVideoCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.thumbnailUrl,
    this.duration,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final String? duration;
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
                    Container(color: Colors.black26, alignment: Alignment.center, child: const Icon(Icons.movie_outlined)),
                  if ((duration ?? '').isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: Text(duration!, style: const TextStyle(fontSize: 12)),
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
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

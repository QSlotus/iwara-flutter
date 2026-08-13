import 'package:flutter/material.dart';

class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.thumbnailUrl,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumbnailUrl == null
                  ? Container(
                      color: const Color(0xFF221F30),
                      child: const Center(child: Icon(Icons.play_circle_outline, size: 40)),
                    )
                  : Image.network(
                      thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF221F30),
                        child: const Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

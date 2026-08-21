import 'package:flutter/material.dart';

/// Subtle attribution overlay shown on top of listing videos ("Posted on
/// Instiy" + store name). Listing videos can't carry a burned-in watermark —
/// text overlay requires re-encoding, which the app's video toolchain can't
/// do — so the watermark is rendered on the players instead. It is small,
/// translucent and non-interactive so it never blocks the content.
class VideoWatermarkOverlay extends StatelessWidget {
  final String? storeName;

  const VideoWatermarkOverlay({super.key, this.storeName});

  @override
  Widget build(BuildContext context) {
    final name = (storeName ?? '').trim();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Text(
                name.length > 24 ? '${name.substring(0, 21)}...' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const Text(
              'Posted on Instiy',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

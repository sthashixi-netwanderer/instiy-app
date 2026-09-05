import 'product_model.dart';
import 'service_model.dart';

/// One entry in the Clips feed — a product clip or a service clip. The feed
/// mixes both into a single PageView; [product] and [service] are mutually
/// exclusive.
class ClipItem {
  final Product? product;
  final Service? service;

  const ClipItem.product(this.product) : service = null;
  const ClipItem.service(this.service) : product = null;

  bool get isService => service != null;

  String get id => isService ? service!.id : product!.id;

  DateTime get createdAt =>
      isService ? service!.createdAt : product!.createdAt;

  /// The video this clip plays: the video pinned for the feed, falling back
  /// to the listing's first video.
  String? get videoUrl {
    if (isService) {
      final s = service!;
      return s.clipVideoUrl ?? (s.videoUrls.isNotEmpty ? s.videoUrls.first : null);
    }
    final p = product!;
    return p.clipVideoUrl ?? (p.videoUrls.isNotEmpty ? p.videoUrls.first : null);
  }

  /// Every video url on the listing — used to evict cached files when the
  /// clip disappears from the feed.
  List<String> get allVideoUrls {
    if (isService) {
      return [...service!.videoUrls, if (service!.clipVideoUrl != null) service!.clipVideoUrl!];
    }
    final p = product!;
    return [...p.videoUrls, if (p.clipVideoUrl != null) p.clipVideoUrl!];
  }
}

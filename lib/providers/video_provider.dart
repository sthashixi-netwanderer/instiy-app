import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clip_item.dart';
import '../models/product_model.dart';
import '../models/service_model.dart';
import '../services/media_cache_service.dart';
import '../services/product_service.dart';
import '../services/service_service.dart';
import '../services/supabase_service.dart';
import '../providers/block_provider.dart';

class VideoProvider extends ChangeNotifier {
  List<ClipItem> _clips = [];
  bool _isLoading = false;
  String? _error;
  int _focusedIndex = 0;
  bool _initialized = false;

  RealtimeChannel? _productsChannel;
  RealtimeChannel? _servicesChannel;

  VideoProvider() {
    _initAuthListener();
    BlockProvider.instance.addListener(_onBlocksChanged);
  }

  void _onBlocksChanged() {
    // Re-fetch from server because unblocked products need to reappear
    refresh();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session == null) {
        _unsubscribeFromRealtime();
        clearSession();
      } else {
        _subscribeToRealtime();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _subscribeToRealtime();
    }
  }

  Future<void> ensureInitialized({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    await loadVideos(silent: _clips.isNotEmpty);
  }

  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    _productsChannel = SupabaseService.client
        .channel('products-changes-video')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            final newProduct = payload.newRecord;
            if (newProduct['status'] != 'available') return;
            if (newProduct['stock_quantity'] == null || newProduct['stock_quantity'] <= 0) return;
            if (newProduct['video_urls'] == null ||
                (newProduct['video_urls'] as List).isEmpty) {
              return;
            }
            loadVideos(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'products',
          callback: (payload) => _handleProductUpdate(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            final deletedId = payload.oldRecord['id'] as String?;
            if (deletedId == null) return;
            _removeClip(deletedId);
          },
        )
        .subscribe();

    _servicesChannel = SupabaseService.client
        .channel('services-changes-video')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'services',
          callback: (payload) {
            final row = payload.newRecord;
            if (row['status'] != 'active') return;
            if (row['show_on_clips'] != true) return;
            final videoUrls = row['video_urls'];
            if (videoUrls == null || (videoUrls as List).isEmpty) return;
            loadVideos(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'services',
          callback: (payload) => _handleServiceUpdate(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'services',
          callback: (payload) {
            final deletedId = payload.oldRecord['id'] as String?;
            if (deletedId == null) return;
            _removeClip(deletedId);
          },
        )
        .subscribe();
  }

  /// Drops a clip whose product was updated so it no longer qualifies for the
  /// clips feed (unavailable, out of stock, removed from clips, video removed).
  void _handleProductUpdate(PostgresChangePayload payload) {
    final record = payload.newRecord;
    final productId = record['id'] as String?;
    if (productId == null) return;
    if (!_clips.any((c) => c.id == productId)) return;

    final videoUrls = record['video_urls'];
    final stillQualifies = record['status'] == 'available' &&
        record['stock_quantity'] != null &&
        record['stock_quantity'] > 0 &&
        record['show_on_clips'] == true &&
        videoUrls != null &&
        (videoUrls as List).isNotEmpty;

    if (!stillQualifies) {
      _removeClip(productId);
    }
  }

  /// Drops a clip whose service was updated so it no longer qualifies for the
  /// clips feed (paused/inactive, removed from clips, video removed).
  void _handleServiceUpdate(PostgresChangePayload payload) {
    final record = payload.newRecord;
    final serviceId = record['id'] as String?;
    if (serviceId == null) return;
    if (!_clips.any((c) => c.id == serviceId)) return;

    final videoUrls = record['video_urls'];
    final stillQualifies = record['status'] == 'active' &&
        record['show_on_clips'] == true &&
        videoUrls != null &&
        (videoUrls as List).isNotEmpty;

    if (!stillQualifies) {
      _removeClip(serviceId);
    }
  }

  /// Removes a clip from the feed, keeps the focused index pointing at the
  /// video the user is currently watching, and evicts the clip's cached video
  /// files so a deleted listing doesn't linger on disk or in the feed.
  void _removeClip(String clipId) {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;

    final removed = _clips[index];
    // A new list instance (not an in-place mutation) so `select` listeners
    // like the feed screen's prefetch subscription actually fire.
    _clips = List.of(_clips)..removeAt(index);

    if (index < _focusedIndex) {
      _focusedIndex--;
    }
    if (_clips.isNotEmpty && _focusedIndex >= _clips.length) {
      _focusedIndex = _clips.length - 1;
    }

    for (final url in removed.allVideoUrls) {
      if (url.isNotEmpty) {
        MediaCacheService.removeFile(url); // ignore: unawaited_futures
      }
    }

    notifyListeners();
  }

  void _unsubscribeFromRealtime() {
    if (_productsChannel != null) {
      SupabaseService.client.removeChannel(_productsChannel!);
      _productsChannel = null;
    }
    if (_servicesChannel != null) {
      SupabaseService.client.removeChannel(_servicesChannel!);
      _servicesChannel = null;
    }
  }

  void clearSession() {
    _clips = [];
    _focusedIndex = 0;
    _isLoading = false;
    _error = null;
    _initialized = false;
    notifyListeners();
  }

  List<ClipItem> get clips => _clips;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get focusedIndex => _focusedIndex;
  bool get isInitialized => _initialized;

  void setFocusedIndex(int index) {
    if (_focusedIndex == index) return;
    _focusedIndex = index;
    notifyListeners();
  }

  Future<void> loadVideos({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final results = await Future.wait([
        ProductService.getClipsProducts(),
        ServiceService.getClipServices(),
      ]);
      final products = results[0] as List<Product>;
      final services = results[1] as List<Service>;

      final blocked = BlockProvider.instance;
      final productClips = blocked
          .filterProducts(products)
          .map(ClipItem.product)
          .toList();
      final serviceClips = services
          .where((s) => !blocked.isUserBlocked(s.providerId))
          .map(ClipItem.service)
          .toList();

      // Newest first across both listing types, like the individual queries.
      final merged = [...productClips, ...serviceClips]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _clips = merged;
      if (_focusedIndex >= _clips.length) {
        _focusedIndex = 0;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadVideos(silent: true);
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    BlockProvider.instance.removeListener(_onBlocksChanged);
    super.dispose();
  }
}

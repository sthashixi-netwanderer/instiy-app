import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/curated_collection_model.dart';
import '../services/curated_collection_service.dart';
import '../services/supabase_service.dart';
import '../providers/block_provider.dart';

class CuratedProvider extends ChangeNotifier {
  List<CuratedCollection> _sections = [];
  bool _isLoading = false;
  String? _error;

  RealtimeChannel? _collectionsChannel;
  Timer? _pollTimer;
  bool _initialized = false;

  List<CuratedCollection> get sections => _sections;
  bool get isLoading => _isLoading;
  String? get error => _error;

  CuratedProvider() {
    // Defer initialization to avoid notifyListeners during build
    Future.microtask(() {
      _init();
    });
    BlockProvider.instance.addListener(_onBlocksChanged);
  }

  void _onBlocksChanged() {
    // Re-fetch and re-filter when block list changes
    _silentReload();
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;
    _subscribeToRealtime();
    _startPolling();
    loadSections();
  }

  /// Ensure initialized when accessed from UI
  void ensureInitialized() {
    if (!_initialized) {
      _init();
    }
  }

  /// Realtime subscription for instant updates
  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    try {
      _collectionsChannel = SupabaseService.client
          .channel('curated-home-${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'curated_collections',
            callback: (_) => _silentReload(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'curated_collection_items',
            callback: (_) => _silentReload(),
          );
      _collectionsChannel!.subscribe();
    } catch (_) {}
  }

  void _unsubscribeFromRealtime() {
    if (_collectionsChannel != null) {
      try {
        SupabaseService.client.removeChannel(_collectionsChannel!);
      } catch (_) {}
      _collectionsChannel = null;
    }
  }

  /// Polling fallback — re-fetch every 30 seconds
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _silentReload();
    });
  }

  Future<void> _silentReload() async {
    try {
      final newSections = await CuratedCollectionService.getHomeSections();
      final blockProv = BlockProvider.instance;
      final filtered = newSections.map((s) {
        final filteredItems = s.items.where((item) {
          if (item.product != null) {
            return !blockProv.isUserBlocked(item.product!.sellerId);
          }
          return true;
        }).toList();
        return CuratedCollection(
          id: s.id, title: s.title,
          subtitle: s.subtitle, icon: s.icon, imageUrl: s.imageUrl,
          displayMode: s.displayMode, contentType: s.contentType,
          maxItems: s.maxItems, sortOrder: s.sortOrder,
          isVisible: s.isVisible, items: filteredItems,
        );
      }).where((s) => s.items.isNotEmpty).toList();
      if (!_sectionsEqual(_sections, filtered)) {
        _sections = filtered;
        notifyListeners();
      }
    } catch (_) {}
  }

  bool _sectionsEqual(List<CuratedCollection> a, List<CuratedCollection> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].title != b[i].title ||
          a[i].isVisible != b[i].isVisible ||
          a[i].sortOrder != b[i].sortOrder ||
          a[i].items.length != b[i].items.length) {
        return false;
      }
    }
    return true;
  }

  Future<void> loadSections() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final raw = await CuratedCollectionService.getHomeSections();
      final blockProv = BlockProvider.instance;
      _sections = raw.map((s) {
        final filteredItems = s.items.where((item) {
          if (item.product != null) {
            return !blockProv.isUserBlocked(item.product!.sellerId);
          }
          return true;
        }).toList();
        return CuratedCollection(
          id: s.id, title: s.title,
          subtitle: s.subtitle, icon: s.icon, imageUrl: s.imageUrl,
          displayMode: s.displayMode, contentType: s.contentType,
          maxItems: s.maxItems, sortOrder: s.sortOrder,
          isVisible: s.isVisible, items: filteredItems,
        );
      }).where((s) => s.items.isNotEmpty).toList();
    } catch (e) {
      // Clean up common Supabase error messages
      var msg = e.toString();
      if (msg.contains('function "get_curated_home_sections" does not exist')) {
        msg = 'Collections feature not set up yet';
      } else if (msg.contains('relation "curated_collections" does not exist')) {
        msg = 'Collections feature not set up yet';
      } else if (msg.length > 100) {
        msg = '${msg.substring(0, 100)}...';
      }
      _error = msg;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called when app resumes from background
  void refresh() {
    ensureInitialized();
    _silentReload();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _unsubscribeFromRealtime();
    BlockProvider.instance.removeListener(_onBlocksChanged);
    super.dispose();
  }
}

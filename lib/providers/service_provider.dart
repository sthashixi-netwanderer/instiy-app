import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_model.dart';
import '../models/category_model.dart';
import '../models/institution_model.dart';
import '../models/service_draft_model.dart';
import '../services/service_service.dart';
import '../services/service_draft_service.dart';
import '../services/institution_service.dart';
import '../services/supabase_service.dart';
import '../services/report_service.dart';

/// Outcome of saving the provider bio from the edit sheet.
enum ProviderBioSaveResult { saved, savedLocally, failed }

/// Outcome of saving the provider public email from the edit sheet.
enum ProviderEmailSaveResult { saved, savedLocally, failed }

/// State for the Services marketplace screen: public browse results, the
/// signed-in creator's own listings, service categories and the provider
/// opt-in flag. Realtime keeps both lists fresh while subscribed.
class ServiceProvider extends ChangeNotifier {
  /// On-device mirror of the provider bio, used only while the hosted
  /// database is missing the service_provider_bio column (its migration
  /// is pending). Cleared as soon as a server save succeeds.
  static const _localBioKey = 'service_provider_bio_local';

  /// On-device mirror of the provider public email, mirroring [_localBioKey].
  static const _localEmailKey = 'service_provider_email_local';

  List<Service> _services = [];
  List<Service> _myServices = [];
  List<Category> _categories = [];
  List<Institution> _institutions = [];
  bool _isLoading = false;
  bool _myServicesLoading = false;
  bool _categoriesLoading = false;
  bool _optingIn = false;

  /// Discover pagination — browse loads in [servicesPageSize] chunks so the
  /// grid (and every realtime refresh of it) never pulls the whole services
  /// table plus its package/review joins in one request.
  static const int servicesPageSize = ServiceService.browsePageSize;

  /// Highest browse page currently held in [_services] (0-based).
  int _servicesPage = 0;
  bool _hasMoreServices = true;
  bool _loadingMoreServices = false;

  String _searchQuery = '';
  String? _selectedCategoryId;
  String? _selectedInstitutionName;
  /// null = not checked yet (signed out or still loading).
  bool? _isServiceProvider;

  /// The signed-in provider's marketplace bio (null when signed out or
  /// not yet a provider).
  String? _providerBio;
  String? _providerEmail;
  String? _error;
  Map<String, dynamic>? _latestAppeal;
  bool _appealSubmitting = false;

  /// Publishing draft for the fire-and-forget service create (reactive for
  /// the My Services tab). Null when nothing is in flight or a publish
  /// finished/cleared.
  ServiceDraftListing? _publishingServiceDraft;
  double _publishProgress = 0;

  RealtimeChannel? _servicesChannel;

  /// Optional freshness signals (category chips, provider-status flips) on
  /// a separate channel — see [_subscribeToRealtime].
  RealtimeChannel? _auxChannel;
  String? _currentUserId;
  bool _loadedOnce = false;
  Timer? _realtimeDebounce;

  /// Monotonic token guarding against out-of-order browse responses —
  /// debounced live search can leave a slower older request in flight when
  /// a newer one resolves first.
  int _browseGeneration = 0;

  ServiceProvider() {
    _subscribeToRealtime();
    _initAuthListener();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        final userId = session.user.id;
        if (_currentUserId == userId) return;
        _currentUserId = userId;
        _subscribeToRealtime();
        checkServiceProviderStatus();
        loadMyServices();
      } else {
        _currentUserId = null;
        _isServiceProvider = null;
        _myServices = [];
        notifyListeners();
        loadServices();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      checkServiceProviderStatus();
      loadMyServices();
    }
  }

  /// Realtime rejects an entire channel when any table it listens to is
  /// missing from the supabase_realtime publication — one un-published
  /// table would silently kill every callback on the channel. The core
  /// listing refresh therefore lives on its own channel, and the optional
  /// signals (categories, users) stay on a second one so they can only
  /// degrade themselves.
  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    _servicesChannel = SupabaseService.client
        .channel('public-services-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'services',
          callback: (payload) => _onRealtimeChange(
            refreshMyListings: _servicesRowMayBeMine(
              payload.newRecord,
              payload.oldRecord,
            ),
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_packages',
          callback: (payload) => _onRealtimeChange(
            refreshMyListings: _childRowMayBeMine(
              payload.newRecord,
              payload.oldRecord,
            ),
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_reviews',
          callback: (payload) => _onRealtimeChange(
            refreshMyListings: _childRowMayBeMine(
              payload.newRecord,
              payload.oldRecord,
            ),
          ),
        );
    _servicesChannel!.subscribe(_onChannelStatus('services'));

    _auxChannel = SupabaseService.client
        .channel('public-services-aux-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          callback: (_) {
            loadCategories(force: true);
            _onRealtimeChange();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            final newRec = payload.newRecord;
            final oldRec = payload.oldRecord;
            final changedUserId =
                newRec['id'] as String? ?? oldRec['id'] as String?;
            if (_currentUserId != null && changedUserId == _currentUserId) {
              checkServiceProviderStatus();
            }
            _onRealtimeChange();
          },
        );
    _auxChannel!.subscribe(_onChannelStatus('aux'));
  }

  /// A failed subscription is otherwise invisible — the screen just stops
  /// receiving updates. Surface it in debug logs so regressions (e.g. a
  /// table dropped from the realtime publication) are noticeable.
  void Function(RealtimeSubscribeStatus, [Object?]) _onChannelStatus(
    String name,
  ) {
    return (RealtimeSubscribeStatus status, [Object? err]) {
      if (status == RealtimeSubscribeStatus.channelError || err != null) {
        debugPrint('ServiceProvider: $name realtime channel $status: $err');
      }
    };
  }

  void _unsubscribeFromRealtime() {
    if (_servicesChannel != null) {
      SupabaseService.client.removeChannel(_servicesChannel!);
      _servicesChannel = null;
    }
    if (_auxChannel != null) {
      SupabaseService.client.removeChannel(_auxChannel!);
      _auxChannel = null;
    }
  }

  void _onRealtimeChange({bool refreshMyListings = true}) {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 250), () {
      _silentReload(refreshMyListings: refreshMyListings);
    });
  }

  /// Whether a services-row change belongs to the signed-in provider. DELETE
  /// payloads only carry the primary key, so a row that doesn't say counts as
  /// "maybe mine" and the dashboard refreshes.
  bool _servicesRowMayBeMine(
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    final mine = _currentUserId;
    if (mine == null) return false;
    final newProvider = newRecord['provider_id'] as String?;
    final oldProvider = oldRecord['provider_id'] as String?;
    if (newProvider == null && oldProvider == null) return true;
    return newProvider == mine || oldProvider == mine;
  }

  /// Whether a service_packages/service_reviews change targets one of the
  /// signed-in provider's own listings (same unknown-payload caveat).
  bool _childRowMayBeMine(
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    final newService = newRecord['service_id'] as String?;
    final oldService = oldRecord['service_id'] as String?;
    if (newService == null && oldService == null) return true;
    final ownIds = _myServices.map((s) => s.id).toSet();
    return ownIds.contains(newService) || ownIds.contains(oldService);
  }

  /// Realtime refresh. Only the rows the user has already scrolled through
  /// are refetched, so the query stays bounded by what is on screen instead
  /// of pulling the whole table on every change anywhere in the marketplace.
  /// The pagination cursor is left untouched so scrolling continues where it
  /// was. [refreshMyListings] additionally reloads the creator dashboard;
  /// callers skip it when the change provably touched another provider.
  Future<void> _silentReload({bool refreshMyListings = true}) async {
    final generation = ++_browseGeneration;
    _loadingMoreServices = false;
    try {
      final page = await ServiceService.getServicesPage(
        categoryId: _selectedCategoryId,
        institutionName: _selectedInstitutionName,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
        limit: (_servicesPage + 1) * servicesPageSize,
      );
      if (generation != _browseGeneration) return;
      final results = page.services;
      _services = _searchQuery.isEmpty ? (results..shuffle()) : results;
      _loadedOnce = true;
      if (_currentUserId != null && refreshMyListings) {
        await checkServiceProviderStatus();
        _myServices = await ServiceService.getMyServices();
      }
      if (generation != _browseGeneration) return;
      notifyListeners();
    } catch (_) {}
  }

  void clearSession() {
    _services = [];
    _myServices = [];
    _error = null;
    _searchQuery = '';
    _selectedCategoryId = null;
    _isServiceProvider = null;
    _latestAppeal = null;
    _loadedOnce = false;
    _servicesPage = 0;
    _hasMoreServices = true;
    _loadingMoreServices = false;
    notifyListeners();
  }

  List<Service> get services => _services;
  List<Service> get myServices => _myServices;
  List<Category> get categories => _categories;
  List<Institution> get institutions => _institutions;
  bool get isLoading => _isLoading;
  bool get hasMoreServices => _hasMoreServices;
  bool get loadingMoreServices => _loadingMoreServices;
  bool get myServicesLoading => _myServicesLoading;
  bool get categoriesLoading => _categoriesLoading;
  bool get optingIn => _optingIn;
  bool get loadedOnce => _loadedOnce;
  String get searchQuery => _searchQuery;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedInstitutionName => _selectedInstitutionName;
  bool? get isServiceProvider => _isServiceProvider;
  bool get isProviderDisabled =>
      (_isServiceProvider == false) &&
      ((_providerBio != null && _providerBio!.trim().isNotEmpty) ||
          _myServices.isNotEmpty);
  String? get providerBio => _providerBio;
  String? get providerEmail => _providerEmail;
  Map<String, dynamic>? get latestAppeal => _latestAppeal;
  bool get appealSubmitting => _appealSubmitting;
  String? get error => _error;
  ServiceDraftListing? get publishingServiceDraft => _publishingServiceDraft;
  double get publishProgress => _publishProgress;

  Category? selectedCategory() {
    final id = _selectedCategoryId;
    if (id == null) return null;
    return _categories.where((c) => c.id == id).firstOrNull;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
    loadServices();
  }

  void setInstitution(String? institutionName) {
    _selectedInstitutionName = institutionName;
    notifyListeners();
    loadServices();
  }

  /// Loads the first browse page (resetting any pagination). [silent] keeps
  /// the previous results visible (no loading flag) — used by live search,
  /// where flashing a skeleton between keystrokes would be jarring. Stale
  /// responses are discarded.
  Future<void> loadServices({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    final generation = ++_browseGeneration;
    _loadingMoreServices = false;

    try {
      final page = await ServiceService.getServicesPage(
        categoryId: _selectedCategoryId,
        institutionName: _selectedInstitutionName,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (generation != _browseGeneration) return;
      // Shuffle the Discover feed so listings share exposure instead of
      // always showing newest-first. Skipped while searching so text matches
      // keep the server's relevance order. Shuffled once per load (not per
      // build), so the grid stays stable while scrolling.
      final results = page.services;
      _services = _searchQuery.isEmpty ? (results..shuffle()) : results;
      _servicesPage = 0;
      _hasMoreServices = page.hasMore;
      _loadedOnce = true;
    } catch (e) {
      if (generation != _browseGeneration) return;
      _error = e.toString();
    } finally {
      if (generation == _browseGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next browse page. Re-entrant calls and calls past the last
  /// page are ignored, and a browse reset (filter/search change or realtime
  /// refresh) invalidates an in-flight page via the generation check.
  Future<void> loadMoreServices() async {
    if (_isLoading || _loadingMoreServices || !_hasMoreServices) return;
    _loadingMoreServices = true;
    notifyListeners();
    final generation = _browseGeneration;

    try {
      final page = await ServiceService.getServicesPage(
        categoryId: _selectedCategoryId,
        institutionName: _selectedInstitutionName,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
        offset: (_servicesPage + 1) * servicesPageSize,
      );
      if (generation != _browseGeneration) return;
      // Another provider publishing mid-scroll shifts the server's offsets,
      // so a row can come back twice — keep the first copy.
      final loadedIds = _services.map((s) => s.id).toSet();
      final fresh = page.services
          .where((s) => !loadedIds.contains(s.id))
          .toList();
      if (_searchQuery.isEmpty) fresh.shuffle();
      _services = [..._services, ...fresh];
      _servicesPage++;
      _hasMoreServices = page.hasMore;
    } catch (_) {
      // Keep the current page loaded; the scroll listener retries on the
      // next scroll gesture.
    } finally {
      if (generation == _browseGeneration) {
        _loadingMoreServices = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadCategories({bool force = false}) async {
    if (_categories.isNotEmpty && !force) return;
    _categoriesLoading = true;
    notifyListeners();

    try {
      _categories = await ServiceService.getServiceCategories();
    } catch (_) {
      // Category chips are optional chrome — browse still works without them.
    } finally {
      _categoriesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadInstitutions() async {
    if (_institutions.isNotEmpty) return;
    try {
      _institutions = await InstitutionService.getInstitutions();
      notifyListeners();
    } catch (_) {
      // Institution filter is optional chrome — ignore failures.
    }
  }

  Future<void> loadMyServices() async {
    if (_currentUserId == null) return;
    _myServicesLoading = true;
    notifyListeners();

    try {
      _myServices = await ServiceService.getMyServices();
    } catch (_) {
      // Surfaced through the screen's empty state; realtime retries anyway.
    } finally {
      _myServicesLoading = false;
      notifyListeners();
    }
  }

  /// Loads the on-device publishing draft into reactive state (called on
  /// screen load, so a publish interrupted by an app kill shows as failed).
  Future<void> loadPublishingServiceDraft() async {
    final draft = await ServiceDraftService.loadDraft();
    _publishingServiceDraft = draft;
    _publishProgress = draft?.progress ?? 0;
    notifyListeners();
  }

  /// Update publishing draft state (called from the background publish).
  void updatePublishingServiceDraft(ServiceDraftListing? draft,
      {double? progress}) {
    _publishingServiceDraft = draft;
    if (progress != null) _publishProgress = progress;
    notifyListeners();
  }

  Future<void> checkServiceProviderStatus() async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      _isServiceProvider = await ServiceService.isServiceProvider();
    } catch (_) {
      _isServiceProvider = null;
    }
    // Tolerant: null (not an error) while the bio column's migration is
    // pending on the hosted database — fall back to the on-device mirror.
    _providerBio = await ServiceService.getProviderBio(userId);
    _providerBio ??= await _readLocalBio();
    _providerEmail = await ServiceService.getProviderEmail(userId);
    _providerEmail ??= await _readLocalEmail();
    if (_isServiceProvider == false) {
      await loadLatestAppeal();
    }
    notifyListeners();
  }

  Future<void> loadLatestAppeal() async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      _latestAppeal = await ReportService.getLatestServiceProviderAppeal();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> submitAppeal(String complaintText) async {
    final text = complaintText.trim();
    if (text.isEmpty) return false;
    _appealSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      await ReportService.submitServiceProviderAppeal(complaintText: text);
      await loadLatestAppeal();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _appealSubmitting = false;
      notifyListeners();
    }
  }

  Future<String?> _readLocalBio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_localBioKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readLocalEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_localEmailKey);
    } catch (_) {
      return null;
    }
  }

  /// Returns true on success; error message otherwise.
  Future<Object> becomeServiceProvider(String bio, String? email) async {
    _optingIn = true;
    notifyListeners();
    try {
      await ServiceService.becomeServiceProvider(bio, email);
      _isServiceProvider = true;
      _providerBio = bio.trim();
      _providerEmail = email?.trim();
      // Keep the opt-in bio/email across restarts even while the server
      // columns are undeployed (the mirror is ignored once the server has
      // the value).
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_localBioKey, _providerBio!);
        if (_providerEmail != null && _providerEmail!.isNotEmpty) {
          await prefs.setString(_localEmailKey, _providerEmail!);
        }
      } catch (_) {}
      await loadMyServices();
      return true;
    } catch (e) {
      return e;
    } finally {
      _optingIn = false;
      notifyListeners();
    }
  }

  /// Saves the provider's public contact email. Mirrors [updateProviderBio]:
  /// [ProviderEmailSaveResult.saved] when the server accepts it,
  /// [ProviderEmailSaveResult.savedLocally] when mirrored on-device because
  /// the server column isn't deployed yet.
  Future<ProviderEmailSaveResult> updateProviderEmail(String email) async {
    final trimmed = email.trim();
    try {
      await ServiceService.updateServiceProviderEmail(trimmed);
      _providerEmail = trimmed.isEmpty ? null : trimmed;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localEmailKey);
      notifyListeners();
      return ProviderEmailSaveResult.saved;
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (trimmed.isEmpty) {
          await prefs.remove(_localEmailKey);
          _providerEmail = null;
        } else {
          await prefs.setString(_localEmailKey, trimmed);
          _providerEmail = trimmed;
        }
        notifyListeners();
        return ProviderEmailSaveResult.savedLocally;
      } catch (_) {
        return ProviderEmailSaveResult.failed;
      }
    }
  }

  /// Saves the provider's marketplace bio. [ProviderBioSaveResult.saved]
  /// means the server accepted it; [ProviderBioSaveResult.savedLocally]
  /// means it was mirrored on-device because the server column isn't
  /// deployed yet (migration pending) — it syncs on the next save once
  /// the column exists.
  Future<ProviderBioSaveResult> updateProviderBio(String bio) async {
    final trimmed = bio.trim();
    try {
      await ServiceService.updateServiceProviderBio(trimmed);
      _providerBio = trimmed;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localBioKey);
      notifyListeners();
      return ProviderBioSaveResult.saved;
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_localBioKey, trimmed);
        _providerBio = trimmed;
        notifyListeners();
        return ProviderBioSaveResult.savedLocally;
      } catch (_) {
        return ProviderBioSaveResult.failed;
      }
    }
  }

  /// Returns true on success; error message otherwise.
  Future<Object> createService({
    required String title,
    required String description,
    required String categoryId,
    required String categoryName,
    required double price,
    String priceType = 'fixed',
    int? deliveryDays,
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
    bool showOnClips = false,
    String? clipVideoUrl,
    List<String> institutionCodes = const [],
    List<String> searchTags = const [],
    List<ServicePackage> packages = const [],
  }) async {
    try {
      await ServiceService.createService(
        title: title,
        description: description,
        categoryId: categoryId,
        categoryName: categoryName,
        price: price,
        priceType: priceType,
        deliveryDays: deliveryDays,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        showOnClips: showOnClips,
        clipVideoUrl: clipVideoUrl,
        institutionCodes: institutionCodes,
        searchTags: searchTags,
        packages: packages,
      );
      await loadMyServices();
      // Realtime also reloads the browse list, but don't depend on it for
      // the user's own action — the Discover tab should update immediately.
      unawaited(loadServices(silent: true));
      return true;
    } catch (e) {
      return e;
    }
  }

  /// Returns true on success; error message otherwise.
  Future<Object> updateService(
    String serviceId, {
    required String title,
    required String description,
    required String categoryId,
    required String categoryName,
    required double price,
    String priceType = 'fixed',
    int? deliveryDays,
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
    bool showOnClips = false,
    String? clipVideoUrl,
    List<String> institutionCodes = const [],
    List<String> searchTags = const [],
    List<ServicePackage> packages = const [],
  }) async {
    try {
      await ServiceService.updateService(
        serviceId,
        title: title,
        description: description,
        categoryId: categoryId,
        categoryName: categoryName,
        price: price,
        priceType: priceType,
        deliveryDays: deliveryDays,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        showOnClips: showOnClips,
        clipVideoUrl: clipVideoUrl,
        institutionCodes: institutionCodes,
        searchTags: searchTags,
        packages: packages,
      );
      await loadMyServices();
      unawaited(loadServices(silent: true));
      return true;
    } catch (e) {
      return e;
    }
  }

  Future<bool> setServiceStatus(String serviceId, ServiceStatus status) async {
    try {
      await ServiceService.setServiceStatus(serviceId, status);
      final index = _myServices.indexWhere((s) => s.id == serviceId);
      if (index >= 0) {
        _myServices[index] = _myServices[index].copyWith(status: status);
        notifyListeners();
      }
      // Pausing hides the listing from Discover; publishing reveals it.
      unawaited(loadServices(silent: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteService(String serviceId) async {
    try {
      await ServiceService.deleteService(serviceId);
      _myServices.removeWhere((s) => s.id == serviceId);
      _services.removeWhere((s) => s.id == serviceId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _unsubscribeFromRealtime();
    super.dispose();
  }
}

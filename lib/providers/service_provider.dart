import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_model.dart';
import '../models/category_model.dart';
import '../models/institution_model.dart';
import '../services/service_service.dart';
import '../services/institution_service.dart';
import '../services/supabase_service.dart';

/// Outcome of saving the provider bio from the edit sheet.
enum ProviderBioSaveResult { saved, savedLocally, failed }

/// State for the Services marketplace screen: public browse results, the
/// signed-in creator's own listings, service categories and the provider
/// opt-in flag. Realtime keeps both lists fresh while subscribed.
class ServiceProvider extends ChangeNotifier {
  /// On-device mirror of the provider bio, used only while the hosted
  /// database is missing the service_provider_bio column (its migration
  /// is pending). Cleared as soon as a server save succeeds.
  static const _localBioKey = 'service_provider_bio_local';

  List<Service> _services = [];
  List<Service> _myServices = [];
  List<Category> _categories = [];
  List<Institution> _institutions = [];
  bool _isLoading = false;
  bool _myServicesLoading = false;
  bool _categoriesLoading = false;
  bool _optingIn = false;
  String _searchQuery = '';
  String? _selectedCategoryId;
  String? _selectedInstitutionName;
  /// null = not checked yet (signed out or still loading).
  bool? _isServiceProvider;

  /// The signed-in provider's marketplace bio (null when signed out or
  /// not yet a provider).
  String? _providerBio;
  String? _error;

  RealtimeChannel? _servicesChannel;
  String? _currentUserId;
  bool _loadedOnce = false;

  ServiceProvider() {
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
        _unsubscribeFromRealtime();
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
      _subscribeToRealtime();
      checkServiceProviderStatus();
      loadMyServices();
    }
  }

  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    _servicesChannel = SupabaseService.client
        .channel('public-services-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'services',
          callback: (_) => _silentReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_packages',
          callback: (_) => _silentReload(),
        );
    _servicesChannel!.subscribe();
  }

  void _unsubscribeFromRealtime() {
    if (_servicesChannel != null) {
      SupabaseService.client.removeChannel(_servicesChannel!);
      _servicesChannel = null;
    }
  }

  Future<void> _silentReload() async {
    try {
      _services = await ServiceService.getServices(
        categoryId: _selectedCategoryId,
        institutionName: _selectedInstitutionName,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (_currentUserId != null) {
        _myServices = await ServiceService.getMyServices();
      }
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
    _loadedOnce = false;
    notifyListeners();
  }

  List<Service> get services => _services;
  List<Service> get myServices => _myServices;
  List<Category> get categories => _categories;
  List<Institution> get institutions => _institutions;
  bool get isLoading => _isLoading;
  bool get myServicesLoading => _myServicesLoading;
  bool get categoriesLoading => _categoriesLoading;
  bool get optingIn => _optingIn;
  bool get loadedOnce => _loadedOnce;
  String get searchQuery => _searchQuery;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedInstitutionName => _selectedInstitutionName;
  bool? get isServiceProvider => _isServiceProvider;
  String? get providerBio => _providerBio;
  String? get error => _error;

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

  Future<void> loadServices() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _services = await ServiceService.getServices(
        categoryId: _selectedCategoryId,
        institutionName: _selectedInstitutionName,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      _loadedOnce = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCategories() async {
    if (_categories.isNotEmpty) return;
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
    notifyListeners();
  }

  Future<String?> _readLocalBio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_localBioKey);
    } catch (_) {
      return null;
    }
  }

  /// Returns true on success; error message otherwise.
  Future<Object> becomeServiceProvider(String bio) async {
    _optingIn = true;
    notifyListeners();
    try {
      await ServiceService.becomeServiceProvider(bio);
      _isServiceProvider = true;
      _providerBio = bio.trim();
      // Keep the opt-in bio across restarts even while the server column
      // is undeployed (the mirror is ignored once the server has a bio).
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_localBioKey, _providerBio!);
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
        institutionCodes: institutionCodes,
        searchTags: searchTags,
        packages: packages,
      );
      await loadMyServices();
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
        institutionCodes: institutionCodes,
        searchTags: searchTags,
        packages: packages,
      );
      await loadMyServices();
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
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteService(String serviceId) async {
    try {
      await ServiceService.deleteService(serviceId);
      _myServices.removeWhere((s) => s.id == serviceId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}

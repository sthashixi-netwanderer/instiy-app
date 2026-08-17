import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_model.dart';
import '../services/service_service.dart';
import '../services/supabase_service.dart';

class ServiceProvider extends ChangeNotifier {
  List<Service> _services = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _error;

  RealtimeChannel? _servicesChannel;
  String? _currentUserId;

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
      } else {
        _unsubscribeFromRealtime();
        _currentUserId = null;
        loadServices();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      _subscribeToRealtime();
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
      final services = await ServiceService.getServices(
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      _services = services;
      notifyListeners();
    } catch (_) {}
  }

  void clearSession() {
    _services = [];
    _error = null;
    _searchQuery = '';
    notifyListeners();
  }

  List<Service> get services => _services;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String? get error => _error;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadServices() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final services = await ServiceService.getServices(
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      _services = services;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import '../services/purchase_permission_service.dart';
import '../services/supabase_service.dart';
import '../services/email_service.dart';

class PurchasePermissionProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _activeLookupResult;
  List<Map<String, dynamic>> _permissionHistory = [];
  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get activeLookupResult => _activeLookupResult;
  List<Map<String, dynamic>> get permissionHistory => _permissionHistory;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get hasMoreHistory => _hasMoreHistory;

  void clearLookupResult() {
    _activeLookupResult = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Generates a code for a product
  Future<String> generateCode({
    required String productId,
    required String sellerId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final code = await PurchasePermissionService.generatePermissionCode(
        productId: productId,
        sellerId: sellerId,
      );
      _isLoading = false;
      notifyListeners();
      return code;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Looks up a permission code and sets the lookup result.
  Future<Map<String, dynamic>?> lookupCode(String code) async {
    _isLoading = true;
    _errorMessage = null;
    _activeLookupResult = null;
    notifyListeners();

    try {
      final result = await PurchasePermissionService.getPermissionByCode(code);
      if (result == null) {
        _errorMessage = 'Invalid or expired permission code.';
      } else {
        _activeLookupResult = result;
      }
      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Grants access based on the permission ID.
  Future<bool> grantAccess(String permissionId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await PurchasePermissionService.grantPermission(permissionId);
      if (_activeLookupResult != null && _activeLookupResult!['id'] == permissionId) {
        _activeLookupResult!['status'] = 'granted';

        final customer = _activeLookupResult!['customer'] as Map<String, dynamic>?;
        final product = _activeLookupResult!['product'] as Map<String, dynamic>?;
        final code = _activeLookupResult!['code'] as String? ?? '';

        final buyerId = customer?['id'] as String?;
        final buyerEmail = customer?['email'] as String?;
        final buyerName = customer?['full_name'] as String? ?? 'Buyer';

        final productTitle = product?['title'] as String? ?? 'Product';
        final productId = product?['id'] as String?;

        // 1. Send in-app notification
        if (buyerId != null) {
          try {
            await SupabaseService.instance.from('notifications').insert({
              'user_id': buyerId,
              'title': 'Access Permission Granted',
              'body': 'You have been granted permission to buy "$productTitle". Code: $code',
              'type': 'permission',
              'data': {
                'permission_id': permissionId,
                'product_id': productId,
                'code': code,
              },
            });
          } catch (e) {
            debugPrint('Failed to send in-app notification: $e');
          }
        }

        // 2. Send email notification
        if (buyerEmail != null && buyerEmail.isNotEmpty) {
          final sellerName = SupabaseService.instance.currentUser?.userMetadata?['full_name'] as String? ?? 'The Seller';
          try {
            await EmailService.sendPurchasePermissionGranted(
              buyerEmail: buyerEmail,
              buyerName: buyerName,
              sellerName: sellerName,
              productTitle: productTitle,
              code: code,
            );
          } catch (e) {
            debugPrint('Failed to send email notification: $e');
          }
        }
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Checks if customer has active permission.
  Future<bool> checkPermissionForProduct(String productId) async {
    try {
      return await PurchasePermissionService.hasActivePermission(productId: productId);
    } catch (_) {
      return false;
    }
  }

  /// Loads permission history for a seller (first page).
  Future<void> loadPermissionHistory(String sellerId) async {
    _isLoadingHistory = true;
    _hasMoreHistory = true;
    _permissionHistory = [];
    notifyListeners();

    try {
      final results = await PurchasePermissionService.getPermissionHistory(
        sellerId: sellerId,
        offset: 0,
        limit: 20,
      );
      _permissionHistory = results;
      _hasMoreHistory = results.length >= 20;
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoadingHistory = false;
    notifyListeners();
  }

  /// Loads next page of permission history.
  Future<void> loadMorePermissionHistory(String sellerId) async {
    if (_isLoadingHistory || !_hasMoreHistory) return;
    _isLoadingHistory = true;
    notifyListeners();

    try {
      final results = await PurchasePermissionService.getPermissionHistory(
        sellerId: sellerId,
        offset: _permissionHistory.length,
        limit: 20,
      );
      _permissionHistory = [..._permissionHistory, ...results];
      _hasMoreHistory = results.length >= 20;
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoadingHistory = false;
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import '../services/purchase_permission_service.dart';
import '../services/supabase_service.dart';
import '../services/email_service.dart';

class PurchasePermissionProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _activeLookupResult;
  List<Map<String, dynamic>> _pendingPermissions = [];
  List<Map<String, dynamic>> _permissionHistory = [];
  bool _isLoadingPending = false;
  bool _hasMorePending = true;
  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get activeLookupResult => _activeLookupResult;
  List<Map<String, dynamic>> get pendingPermissions => _pendingPermissions;
  List<Map<String, dynamic>> get permissionHistory => _permissionHistory;
  bool get isLoadingPending => _isLoadingPending;
  bool get hasMorePending => _hasMorePending;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get hasMoreHistory => _hasMoreHistory;

  void clearLookupResult() {
    _activeLookupResult = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Inserts an in-app notification via the create_notification RPC.
  ///
  /// Direct inserts into public.notifications are blocked by RLS (the table
  /// has no INSERT policy), so clients must go through this SECURITY DEFINER
  /// RPC. The push-notification trigger still fires inside it.
  Future<void> _createNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    await SupabaseService.client.rpc('create_notification', params: {
      'p_user_id': userId,
      'p_title': title,
      'p_body': body,
      'p_type': type,
      'p_data': data ?? {},
    });
  }

  /// Generates a code for a product and notifies the seller.
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

      // Notify the seller via email and in-app notification. Each channel
      // fails independently so one can't suppress the other.
      final buyer = SupabaseService.instance.currentUser;
      final buyerName = buyer?.userMetadata?['full_name'] as String? ?? 'A buyer';

      Map<String, dynamic>? sellerData;
      try {
        sellerData = await SupabaseService.table('users')
            .select('full_name, email')
            .eq('id', sellerId)
            .maybeSingle();
      } catch (e) {
        debugPrint('Failed to fetch seller for notification: $e');
      }

      final sellerName = sellerData?['full_name'] as String? ?? 'Seller';
      final sellerEmail = sellerData?['email'] as String? ?? '';

      // In-app notification to seller.
      try {
        await _createNotification(
          userId: sellerId,
          title: 'Purchase Permission Request',
          body: '$buyerName wants to buy a product from you. Open Buyer Permissions to review.',
          type: 'permission',
          data: {
            'code': code,
            'product_id': productId,
            'buyer_id': buyer?.id,
          },
        );
      } catch (e) {
        debugPrint('Failed to send in-app notification: $e');
      }

      // Email to seller.
      if (sellerEmail.isNotEmpty) {
        try {
          final productData = await SupabaseService.table('products')
            .select('title')
            .eq('id', productId)
            .maybeSingle();
          final productTitle = productData?['title'] as String? ?? 'a product';

          await EmailService.sendPurchasePermissionRequested(
            sellerEmail: sellerEmail,
            sellerName: sellerName,
            buyerName: buyerName,
            productTitle: productTitle,
            code: code,
          );
        } catch (e) {
          debugPrint('Failed to send email notification: $e');
        }
      }

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

  /// Grants access based on the permission ID with custom expiry.
  Future<bool> grantAccess(String permissionId, {Duration expiry = const Duration(hours: 24)}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await PurchasePermissionService.grantPermission(permissionId, expiry: expiry);
      if (_activeLookupResult != null && _activeLookupResult!['id'] == permissionId) {
        _activeLookupResult!['status'] = 'granted';
      }

      // Sellers can grant from the code-lookup screen or straight from the
      // pending list, so resolve buyer/product details from whichever is loaded.
      Map<String, dynamic>? perm;
      if (_activeLookupResult != null && _activeLookupResult!['id'] == permissionId) {
        perm = _activeLookupResult;
      } else {
        for (final p in _pendingPermissions) {
          if (p['id'] == permissionId) {
            perm = p;
            break;
          }
        }
      }

      if (perm != null) {
        final customer = perm['customer'] as Map<String, dynamic>?;
        final product = perm['product'] as Map<String, dynamic>?;
        final code = perm['code'] as String? ?? '';

        final buyerId = customer?['id'] as String?;
        final buyerEmail = customer?['email'] as String?;
        final buyerName = customer?['full_name'] as String? ?? 'Buyer';

        final productTitle = product?['title'] as String? ?? 'Product';
        final productId = product?['id'] as String?;

        // 1. Send in-app notification
        if (buyerId != null) {
          try {
            await _createNotification(
              userId: buyerId,
              title: 'Access Permission Granted',
              body: 'You have been granted permission to buy "$productTitle". Code: $code',
              type: 'permission',
              data: {
                'permission_id': permissionId,
                'product_id': productId,
                'code': code,
              },
            );
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
              duration: expiry,
              productId: productId ?? '',
            );
          } catch (e) {
            debugPrint('Failed to send email notification: $e');
          }
        }
      }

      // Remove from pending list.
      _pendingPermissions.removeWhere((p) => p['id'] == permissionId);

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

  /// Cancels/rejects a permission request and notifies the buyer.
  Future<bool> cancelAccess(String permissionId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get the permission details before cancelling for notification.
      final perm = _pendingPermissions.firstWhere(
        (p) => p['id'] == permissionId,
        orElse: () => {},
      );

      await PurchasePermissionService.cancelPermission(permissionId);

      // Notify the buyer.
      final customer = perm['customer'] as Map<String, dynamic>?;
      final product = perm['product'] as Map<String, dynamic>?;
      final buyerId = customer?['id'] as String?;
      final buyerEmail = customer?['email'] as String?;
      final buyerName = customer?['full_name'] as String? ?? 'Buyer';
      final productTitle = product?['title'] as String? ?? 'Product';
      final productId = product?['id'] as String?;

      if (buyerId != null) {
        try {
          await _createNotification(
            userId: buyerId,
            title: 'Permission Request Declined',
            body: 'Your permission request for "$productTitle" was declined by the seller.',
            type: 'permission',
            data: {
              'permission_id': permissionId,
              'product_id': productId,
            },
          );
        } catch (e) {
          debugPrint('Failed to send in-app notification: $e');
        }
      }

      if (buyerEmail != null && buyerEmail.isNotEmpty) {
        final sellerName = SupabaseService.instance.currentUser?.userMetadata?['full_name'] as String? ?? 'The Seller';
        try {
          await EmailService.sendPurchasePermissionRejected(
            buyerEmail: buyerEmail,
            buyerName: buyerName,
            sellerName: sellerName,
            productTitle: productTitle,
          );
        } catch (e) {
          debugPrint('Failed to send email notification: $e');
        }
      }

      // Remove from pending list.
      _pendingPermissions.removeWhere((p) => p['id'] == permissionId);

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

  /// Revokes a previously granted permission and notifies the buyer.
  Future<bool> revokeAccess(String permissionId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get the permission details before revoking for notification.
      final perm = _permissionHistory.firstWhere(
        (p) => p['id'] == permissionId,
        orElse: () => {},
      );

      await PurchasePermissionService.revokePermission(permissionId);

      // Notify the buyer.
      final customer = perm['customer'] as Map<String, dynamic>?;
      final product = perm['product'] as Map<String, dynamic>?;
      final buyerId = customer?['id'] as String?;
      final buyerEmail = customer?['email'] as String?;
      final buyerName = customer?['full_name'] as String? ?? 'Buyer';
      final productTitle = product?['title'] as String? ?? 'Product';
      final productId = product?['id'] as String?;

      if (buyerId != null) {
        try {
          await _createNotification(
            userId: buyerId,
            title: 'Access Permission Revoked',
            body: 'Your permission to buy "$productTitle" has been revoked by the seller.',
            type: 'permission',
            data: {
              'permission_id': permissionId,
              'product_id': productId,
            },
          );
        } catch (e) {
          debugPrint('Failed to send in-app notification: $e');
        }
      }

      if (buyerEmail != null && buyerEmail.isNotEmpty) {
        final sellerName = SupabaseService.instance.currentUser?.userMetadata?['full_name'] as String? ?? 'The Seller';
        try {
          await EmailService.sendPurchasePermissionRevoked(
            buyerEmail: buyerEmail,
            buyerName: buyerName,
            sellerName: sellerName,
            productTitle: productTitle,
          );
        } catch (e) {
          debugPrint('Failed to send email notification: $e');
        }
      }

      // Reflect the new status in place so the history tile updates.
      final index = _permissionHistory.indexWhere((p) => p['id'] == permissionId);
      if (index != -1) {
        _permissionHistory[index]['status'] = 'revoked';
        _permissionHistory[index]['expires_at'] = DateTime.now().toUtc().toIso8601String();
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

  /// Checks if customer has a pending permission request for a product.
  Future<bool> checkPendingPermission(String productId) async {
    try {
      return await PurchasePermissionService.hasPendingPermission(productId: productId);
    } catch (_) {
      return false;
    }
  }

  /// Loads pending permission requests for a seller (first page).
  Future<void> loadPendingPermissions(String sellerId) async {
    _isLoadingPending = true;
    _hasMorePending = true;
    _pendingPermissions = [];
    notifyListeners();

    try {
      final results = await PurchasePermissionService.getPendingPermissions(
        sellerId: sellerId,
        offset: 0,
        limit: 20,
      );
      _pendingPermissions = results;
      _hasMorePending = results.length >= 20;
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoadingPending = false;
    notifyListeners();
  }

  /// Loads next page of pending permissions.
  Future<void> loadMorePendingPermissions(String sellerId) async {
    if (_isLoadingPending || !_hasMorePending) return;
    _isLoadingPending = true;
    notifyListeners();

    try {
      final results = await PurchasePermissionService.getPendingPermissions(
        sellerId: sellerId,
        offset: _pendingPermissions.length,
        limit: 20,
      );
      _pendingPermissions = [..._pendingPermissions, ...results];
      _hasMorePending = results.length >= 20;
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoadingPending = false;
    notifyListeners();
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

/// Cross-institution purchase rules, shared by every add-to-cart surface.
///
/// A product is restricted for a buyer when it is listed on campuses that
/// don't include the buyer's institution. Mirrors the logic in
/// `ProductDetailScreen._isCrossInstitution`; the active-permission bypass
/// is handled separately (product detail screen and CartProvider enforce it
/// via `PurchasePermissionService.hasActivePermission`).
class PurchaseAccess {
  PurchaseAccess._();

  /// Whether [campuses] excludes [userUniversity] for this buyer.
  ///
  /// Empty campuses means the seller hasn't restricted the product to any
  /// campus, and an empty/unknown buyer institution can't be compared —
  /// neither is restricted.
  static bool isRestrictedForBuyer({
    required List<String> campuses,
    required String? userUniversity,
  }) {
    if (userUniversity == null || userUniversity.trim().isEmpty) return false;
    if (campuses.isEmpty) return false;
    final normalized = userUniversity.toLowerCase().trim();
    return !campuses.any((c) => c.toLowerCase().trim() == normalized);
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/service_draft_model.dart';

/// Persistence for the fire-and-forget service publish. Mirrors the
/// product DraftService, with a longer stale-publish window since service
/// videos are compressed and trimmed before upload.
class ServiceDraftService {
  static const _draftKey = 'service_listing_draft';

  static Future<ServiceDraftListing?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_draftKey);
    if (json == null) return null;

    try {
      final draft =
          ServiceDraftListing.fromJson(jsonDecode(json) as Map<String, dynamic>);
      // Stale-publish detection: if no progress save landed for over 5
      // minutes and the draft is still "publishing", the app was likely
      // killed mid-upload — surface it as failed.
      if (draft.status == ServiceDraftStatus.publishing &&
          DateTime.now().difference(draft.savedAt).inMinutes > 5) {
        final failed = draft.copyWith(
          status: ServiceDraftStatus.failed,
          errorMessage: 'Publish was interrupted. Please try again.',
        );
        await saveDraft(failed);
        return failed;
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDraft(ServiceDraftListing draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
  }

  static Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}

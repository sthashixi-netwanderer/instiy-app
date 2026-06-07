import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/draft_listing_model.dart';

class DraftService {
  static const _draftKey = 'listing_draft';

  static Future<DraftListing?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_draftKey);
    if (json == null) return null;

    try {
      final draft = DraftListing.fromJson(jsonDecode(json) as Map<String, dynamic>);
      // Stale-publishing detection: if saved > 2 min ago and still "publishing", mark as failed
      if (draft.status == DraftStatus.publishing &&
          DateTime.now().difference(draft.savedAt).inMinutes > 2) {
        final failed = draft.copyWith(
          status: DraftStatus.failed,
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

  static Future<void> saveDraft(DraftListing draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
  }

  static Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}

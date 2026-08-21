import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'supabase_service.dart';

/// A resolved Ghana Post GPS location.
class GhanaPostLocation {
  final double lat;
  final double lng;
  final String area;

  const GhanaPostLocation({
    required this.lat,
    required this.lng,
    required this.area,
  });

  /// Google Maps embed URL for this location (same format the admin panel's
  /// GPS settings preview uses).
  String get mapEmbedUrl =>
      'https://maps.google.com/maps?q=$lat,$lng&z=15&output=embed';

  /// Universal Google Maps URL for opening the location externally.
  String get externalMapsUrl => 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
}

/// Resolves Ghana Post digital addresses (e.g. GA-492-8490) to coordinates
/// using the GhanaPost GPS API. Credentials come from the `ghanapost_config`
/// table, maintained from the admin panel's GPS settings page.
class GhanaPostService {
  static const _fallbackGpsUrl = 'https://mijoride.ghanapostgps.com/user/get_address';

  static String? _apiUrl;
  static String? _apiToken;

  static Future<void> _loadConfig() async {
    try {
      final res = await SupabaseService.table('ghanapost_config').select();
      for (final item in res) {
        if (item['key'] == 'api_url') {
          _apiUrl = item['value'] as String;
        } else if (item['key'] == 'api_token') {
          _apiToken = item['value'] as String;
        }
      }
    } catch (e) {
      debugPrint('GhanaPostService: failed to load config: $e');
    }
  }

  /// Resolves [address] to a location, or returns null when the address
  /// can't be resolved. Never throws.
  static Future<GhanaPostLocation?> resolve(String address) async {
    final cleaned = address.trim().toUpperCase();
    if (cleaned.isEmpty) return null;

    try {
      if (_apiUrl == null) {
        await _loadConfig();
      }

      // Validate the API URL to prevent URL injection from a compromised DB
      // record. Only allow https:// URLs; fall back to the known-good default.
      final rawUrl = _apiUrl ?? _fallbackGpsUrl;
      final validatedUri = Uri.tryParse(rawUrl);
      final url = (validatedUri != null && validatedUri.scheme == 'https')
          ? rawUrl
          : _fallbackGpsUrl;
      // No hardcoded fallback token — if not loaded, the request will fail
      // gracefully with a 401 rather than using a leaked credential.
      final token = _apiToken ?? '';

      // Uri.replace safely encodes the address parameter (prevents
      // query-string injection).
      final uri = Uri.parse(url).replace(queryParameters: {'address': cleaned});
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data == null) return null;
      final result = (data['Result'] is Map)
          ? data['Result'] as Map<String, dynamic>
          : (data['result'] is Map)
              ? data['result'] as Map<String, dynamic>
              : data as Map<String, dynamic>;

      if (result['GPSName'] == null && result['CenterLatitude'] == null) {
        return null;
      }

      final lat = result['CenterLatitude'] != null
          ? double.tryParse(result['CenterLatitude'].toString())
          : null;
      final lng = result['CenterLongitude'] != null
          ? double.tryParse(result['CenterLongitude'].toString())
          : null;
      if (lat == null || lng == null) return null;

      final street = result['Street'] ?? '';
      final region = result['Region'] ?? '';
      final district = result['District'] ?? '';
      final community = result['Community'] ?? '';
      final breakdown = [
        if (street.toString().isNotEmpty) 'Street: $street',
        if (community.toString().isNotEmpty) 'Community: $community',
        if (district.toString().isNotEmpty) 'District: $district',
        if (region.toString().isNotEmpty) 'Region: $region',
      ].join(', ');

      return GhanaPostLocation(
        lat: lat,
        lng: lng,
        area: breakdown.isNotEmpty ? breakdown : 'Coordinates resolved: ($lat, $lng)',
      );
    } catch (e) {
      debugPrint('GhanaPostService: failed to resolve "$cleaned": $e');
      return null;
    }
  }

  /// Extracts coordinates from a stored Google Maps URL's `q` parameter
  /// (e.g. "https://maps.google.com/maps?q=5.6037,-0.1870&...").
  static (double, double)? coordsFromMapsUrl(String url) {
    final uri = Uri.tryParse(url);
    final q = uri?.queryParameters['q'];
    if (q == null) return null;
    final parts = q.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }
}

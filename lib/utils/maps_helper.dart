/// Helper for loading Google Maps URLs in WebViews.
class MapsHelper {
  /// Loads a Google Maps URL directly in a WebView (not in an iframe).
  ///
  /// Google Maps blocks iframe embedding via X-Frame-Options, so we load
  /// the URL directly. Shortened URLs (maps.app.goo.gl) will redirect
  /// to the full map automatically.
  static Uri toWebViewUri(String mapsUrl) {
    return Uri.parse(mapsUrl);
  }

  /// Validates whether a string looks like a Google Maps URL.
  static bool isGoogleMapsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('google.com/maps') ||
        lower.contains('maps.app.goo.gl') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('maps.google.com');
  }
}

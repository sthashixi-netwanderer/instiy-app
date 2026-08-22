import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Embedded Google Maps preview of a store location — the mobile equivalent
/// of the admin panel's map iframe (`maps.google.com/maps?q=...&output=embed`).
/// Provide either [lat]/[lng] or a free-text [query] (address text).
class StoreMapPreview extends StatefulWidget {
  final double? lat;
  final double? lng;
  final String? query;
  final double height;

  const StoreMapPreview({
    super.key,
    this.lat,
    this.lng,
    this.query,
    this.height = 200,
  });

  @override
  State<StoreMapPreview> createState() => _StoreMapPreviewState();
}

class _StoreMapPreviewState extends State<StoreMapPreview> {
  late final WebViewController _controller;
  late final String _embedUrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final q = (widget.query != null && widget.query!.isNotEmpty)
        ? Uri.encodeComponent(widget.query!)
        : '${widget.lat},${widget.lng}';
    _embedUrl = 'https://maps.google.com/maps?q=$q&z=15&output=embed';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onNavigationRequest: (request) {
            // The wrapper document itself loads as about:blank (empty host).
            // Keep the WebView on the map embed — external links are opened
            // by the dedicated buttons next to the preview.
            final host = Uri.tryParse(request.url)?.host ?? '';
            final isMapsRelated = host.isEmpty ||
                host.endsWith('google.com') ||
                host.endsWith('gstatic.com') ||
                host.endsWith('googleapis.com') ||
                host.endsWith('googleusercontent.com') ||
                host.endsWith('googleadservices.com') ||
                host.endsWith('goo.gl');
            return isMapsRelated
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      // Load a minimal HTML page whose <iframe> points at the embed URL —
      // NOT the embed URL directly. Google's Maps Embed endpoint refuses to
      // render as a top-level document ("The Google Maps Embed API must be
      // used in an iframe"); it only works inside a real iframe element,
      // which is exactly how the admin panel's GPS settings page embeds it.
      ..loadHtmlString(_buildEmbedHtml(_embedUrl));
  }

  /// Mirrors the admin panel's GPS settings iframe markup (GPSConfig.tsx):
  /// a full-viewport, borderless iframe over a zero-margin body.
  String _buildEmbedHtml(String embedUrl) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <title>Store Map Preview</title>
  <style>
    html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; background: #ffffff; }
    iframe { border: 0; width: 100%; height: 100%; display: block; }
  </style>
</head>
<body>
  <iframe
    src="$embedUrl"
    loading="lazy"
    referrerpolicy="no-referrer-when-downgrade"
    allowfullscreen
  ></iframe>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (!_loaded)
              const ColoredBox(
                color: Colors.black12,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }
}

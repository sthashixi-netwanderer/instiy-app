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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onNavigationRequest: (request) {
            // Keep the WebView on the map embed — external links are opened
            // by the dedicated buttons next to the preview.
            final host = Uri.parse(request.url).host;
            final isMapsRelated = host.endsWith('google.com') ||
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
      ..loadRequest(Uri.parse(_embedUrl));
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

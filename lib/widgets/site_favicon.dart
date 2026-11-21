/// Real favicon widget for CubicWeb Browser.
///
/// Browsers never fall back to a hard-coded "demo" globe: this widget resolves
/// the site's own icon (captured from the live tab when possible), then tries
/// Google's favicon service and finally the site's `/favicon.ico`. Only when
/// every source fails does it draw the neutral fallback icon.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Displays the favicon for [url] at [size], falling back through several
/// sources before showing [fallbackIcon].
class SiteFavicon extends StatelessWidget {
  final String url;
  final String? faviconUrl;
  final double size;
  final IconData fallbackIcon;
  final Color? fallbackColor;
  final BorderRadius borderRadius;
  final BoxFit fit;

  const SiteFavicon({
    super.key,
    required this.url,
    this.faviconUrl,
    this.size = 20,
    this.fallbackIcon = LucideIcons.globe,
    this.fallbackColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.fit = BoxFit.contain,
  });

  static String _hostOf(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      final host = uri.host.toLowerCase().replaceFirst('www.', '');
      return host;
    } catch (_) {
      return '';
    }
  }

  List<String> _candidates() {
    final host = _hostOf(url);
    if (host.isEmpty) return <String>[];

    final hosts = <String>[host];
    // e.g. news.example.com often shares example.com's icon.
    final parts = host.split('.');
    if (parts.length > 2) hosts.add(parts.sublist(1).join('.'));

    final out = <String>[];
    void add(String? u) {
      if (u == null || u.isEmpty) return;
      final lower = u.toLowerCase();
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        return; // image network cannot load relative/data/blob URLs here
      }
      if (!out.contains(u)) out.add(u);
    }

    // 1. Exact icon declared by the page (absolute URL from the live DOM).
    add(faviconUrl);
    // 2. Google S2 (no CORS, stable CDN).
    for (final h in hosts) {
      add('https://www.google.com/s2/favicons?domain=$h&sz=64');
    }
    // 3. The classic location on the site itself.
    for (final h in hosts) {
      add('https://$h/favicon.ico');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Icon(fallbackIcon, size: size * 0.85, color: fallbackColor);

    // Wrap in reverse so the first candidate is the outermost Image: an error
    // simply reveals the next candidate, and the globe is the last resort.
    for (final candidate in _candidates().reversed) {
      child = Image.network(
        candidate,
        width: size,
        height: size,
        fit: fit,
        cacheWidth: (size * 3).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => child,
        loadingBuilder: (_, widget, progress) {
          if (progress == null) return widget;
          // Don't flash the globe while the real icon is in flight.
          return SizedBox(
            width: size,
            height: size,
            child: Center(
              child: SizedBox(
                width: size * 0.7,
                height: size * 0.7,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: fallbackColor ?? Theme.of(context).hintColor,
                ),
              ),
            ),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

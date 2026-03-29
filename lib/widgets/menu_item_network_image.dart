import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Reads dish image URL from Firestore menu docs (camelCase or legacy snake_case).
String? menuItemImageUrlFromMap(Map<String, dynamic> item) {
  for (final key in ['imageUrl', 'image_url', 'photoUrl', 'image']) {
    final v = item[key];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty && s != 'null') {
      return _normalizeImageUrl(s);
    }
  }
  return null;
}

/// Fixes occasional bad saves and helps with mixed-content / encoding issues.
String _normalizeImageUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  if (s.startsWith('http://firebasestorage.googleapis.com')) {
    s = 'https://${s.substring('http://'.length)}';
  }
  return s;
}

/// Network image for menu rows / previews: stable key, loading + error fallbacks.
class MenuItemNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget placeholder;
  final double? width;
  final double? height;

  const MenuItemNetworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.placeholder,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final clean = _normalizeImageUrl(url);
    if (clean.isEmpty) return placeholder;
    return Image.network(
      clean,
      key: ValueKey<String>(clean),
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return placeholder;
      },
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}

Widget menuItemImageOrPlaceholder({
  required BuildContext context,
  required Map<String, dynamic> item,
  required double size,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final placeholder = Container(
    width: size,
    height: size,
    color: theme.colorScheme.primary.withValues(alpha: 0.1),
    child: Icon(
      RadixIcons.reader,
      size: size * 0.375,
      color: theme.colorScheme.primary,
    ),
  );
  final url = menuItemImageUrlFromMap(item);
  final child = url != null && url.isNotEmpty
      ? MenuItemNetworkImage(
          url: url,
          fit: BoxFit.cover,
          width: size,
          height: size,
          placeholder: placeholder,
        )
      : placeholder;
  if (borderRadius != null) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: size, height: size, child: child),
    );
  }
  return SizedBox(width: size, height: size, child: child);
}

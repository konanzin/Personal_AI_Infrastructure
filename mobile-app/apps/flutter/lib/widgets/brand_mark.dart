import 'package:flutter/material.dart';

/// Central place to plug the PAI brand mark shown on the empty chat screen.
///
/// No artwork ships yet, so this renders an empty reserved slot — the home
/// screen already lays out space for it, so dropping the mark in later won't
/// reflow the layout.
///
/// To add the mark: drop an image into `assets/images/` (already declared in
/// pubspec) and point [markAsset] at it (e.g. in `main()`:
/// `BrandMark.markAsset = 'assets/images/pai_mark.png';`). PNG/JPG load via
/// [Image.asset] out of the box. For an SVG, add the `flutter_svg` dependency
/// and swap the loader in [_buildArt]. Keep [tinted] true for a single-color
/// silhouette (recolored with the theme gradient); false for full-color art.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88, this.tinted = true});

  /// Reserved square size for the mark.
  final double size;

  /// When true, recolors an opaque-silhouette asset with a theme gradient
  /// (primary → tertiary) so it follows the active seed / dynamic color.
  final bool tinted;

  /// Path to the brand-mark asset. Empty reserves the slot without art.
  static String markAsset = 'assets/images/pai_mark.png';

  @override
  Widget build(BuildContext context) {
    if (markAsset.isEmpty) {
      // Reserve the slot so adding the mark later doesn't shift the greeting.
      return SizedBox(height: size);
    }

    final art = _buildArt(markAsset);
    if (!tinted) return art;

    final scheme = Theme.of(context).colorScheme;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [scheme.primary, scheme.tertiary],
      ).createShader(rect),
      child: art,
    );
  }

  Widget _buildArt(String asset) =>
      Image.asset(asset, width: size, height: size, fit: BoxFit.contain);
}

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Centered logo + titles for the launch splash (SD-lib, on photo backdrop).
class SdLibSplashBranding extends StatelessWidget {
  const SdLibSplashBranding({
    super.key,
    this.logoAsset = 'assets/speakdine_logo.png',
    this.logoSize = 120,
    this.title = 'SpeakDine',
    this.tagline = 'Dine with ease',
  });

  final String logoAsset;
  final double logoSize;
  final String title;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          logoAsset,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tagline,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

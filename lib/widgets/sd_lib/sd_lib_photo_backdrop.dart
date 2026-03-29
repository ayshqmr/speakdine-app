import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Full-bleed photo + scrim used on auth and splash (SD-lib shell).
class SdLibPhotoBackdrop extends StatelessWidget {
  const SdLibPhotoBackdrop({
    super.key,
    this.imageAsset = 'assets/splash.png',
    this.scrimOpacity = 0.35,
  });

  final String imageAsset;
  final double scrimOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(imageAsset),
              fit: BoxFit.cover,
            ),
          ),
        ),
        ColoredBox(
          color: Colors.black.withValues(alpha: scrimOpacity),
        ),
      ],
    );
  }
}

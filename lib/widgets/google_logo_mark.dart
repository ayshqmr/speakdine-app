import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Multicolor Google "G" (brand colors) for Sign in with Google buttons.
class GoogleLogoMark extends StatelessWidget {
  const GoogleLogoMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/google_logo.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

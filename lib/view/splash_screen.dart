import 'package:flutter/scheduler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/view/splash/splash_navigation.dart';
import 'package:speak_dine/widgets/sd_lib/sd_lib_photo_backdrop.dart';
import 'package:speak_dine/widgets/sd_lib/sd_lib_splash_branding.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final Animation<double> _fadeAnimation = Tween<double>(begin: 0, end: 1)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

  @override
  void initState() {
    super.initState();
    _controller.forward();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      navigateFromSplash(context);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SdLibPhotoBackdrop(),
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: const SdLibSplashBranding(),
            ),
          ),
        ],
      ),
    );
  }
}

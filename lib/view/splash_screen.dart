import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/view/authScreens/login_view.dart';
import 'package:speak_dine/view/home/customer_shell.dart';
import 'package:speak_dine/view/home/restaurant_shell.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
    _navigationTimer = Timer(
      const Duration(seconds: 2),
      _navigateAfterDelay,
    );
  }

  Future<void> _navigateAfterDelay() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _routeByRole(user.uid);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginView()),
      );
    }
  }

  Future<void> _routeByRole(String uid) async {
    final firestore = FirebaseFirestore.instance;

    final restaurantDoc =
        await firestore.collection('restaurants').doc(uid).get();
    if (restaurantDoc.exists && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RestaurantShell()),
      );
      return;
    }

    final userDoc = await firestore.collection('users').doc(uid).get();
    if (userDoc.exists && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerShell()),
      );
      return;
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginView()),
      );
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      child: Container(
        color: theme.colorScheme.background,
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/speakdine_logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                const Text('SpeakDine').h2().semiBold(),
                const SizedBox(height: 8),
                const Text('Dine with ease').muted().small(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

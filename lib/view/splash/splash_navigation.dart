import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/view/authScreens/login_view.dart';
import 'package:speak_dine/view/home/customer_shell.dart';
import 'package:speak_dine/view/home/restaurant_shell.dart';

/// Routes after splash delay based on Firebase session and Firestore role docs.
Future<void> navigateFromSplash(BuildContext context) async {
  await Future.delayed(const Duration(seconds: 2));
  if (!context.mounted) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const LoginView()),
    );
    return;
  }

  await _routeByRole(context, user.uid);
}

Future<void> _routeByRole(BuildContext context, String uid) async {
  final firestore = FirebaseFirestore.instance;

  final restaurantDoc =
      await firestore.collection('restaurants').doc(uid).get();
  if (restaurantDoc.exists && context.mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const RestaurantShell()),
    );
    return;
  }

  final userDoc = await firestore.collection('users').doc(uid).get();
  if (userDoc.exists && context.mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const CustomerShell()),
    );
    return;
  }

  if (context.mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const LoginView()),
    );
  }
}

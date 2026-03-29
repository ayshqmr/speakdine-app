import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' as material
    show AlertDialog, Text, TextButton;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/view/home/customer_shell.dart';
import 'package:speak_dine/view/home/restaurant_shell.dart';
import 'package:speak_dine/view/authScreens/signup_view.dart';
import 'package:speak_dine/view/authScreens/forgot_password_view.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/widgets/auth_labeled_text_field.dart';
import 'package:speak_dine/services/google_auth_service.dart';
import 'package:speak_dine/services/login_identifier_service.dart';
import 'package:speak_dine/services/login_lookup_sync.dart';
import 'package:speak_dine/utils/google_sign_in_guard.dart';
import 'package:speak_dine/widgets/google_logo_mark.dart';
import 'package:speak_dine/widgets/keyboard_friendly.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _identifierController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Resolves the input into an email address (server Admin lookup for names;
  /// Firestore client rules block pre-auth queries).
  Future<String?> _resolveEmail(String emailOrUsername) async {
    final value = emailOrUsername.trim();
    if (value.isEmpty) return null;
    if (value.contains('@')) return value;
    return LoginIdentifierService.resolveToEmail(value);
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      _showMessage('Please enter email and password');
      return;
    }

    setState(() => _loading = true);

    try {
      final email = await _resolveEmail(identifier);
      if (email == null) {
        _showMessage(
          'No account matches that email. Check spelling or sign up.',
        );
        return;
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;
      final uid = credential.user?.uid;
      if (uid == null) {
        _showMessage('Login failed');
        return;
      }

      // Gate routing until email is verified.
      final emailVerified = credential.user?.emailVerified ?? false;
      if (!emailVerified) {
        _showMessage('Please verify your email before logging in.');
        await _auth.signOut();
        return;
      }

      await _routeByRole(uid);
    } on FirebaseAuthException catch (e) {
      _showMessage(_authErrorMessage(e.code));
    } catch (_) {
      _showMessage('Something went wrong. Please wait and try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_loading) return;
    if (isGoogleSignInMissingAndroidWebClientId) {
      _showMessage(googleSignInMissingWebClientIdMessage);
      return;
    }
    setState(() => _loading = true);
    try {
      final routeType = await GoogleAuthService().signInWithGoogleAndUpsert(
        defaultCustomer: true,
      );
      if (routeType == null) return;

      final user = _auth.currentUser;
      if (user == null) {
        _showMessage('Login failed');
        return;
      }

      // Gate routing until email is verified.
      if (!user.emailVerified) {
        _showMessage('Please verify your email before logging in.');
        await _auth.signOut();
        return;
      }

      await _routeByRole(user.uid);
    } catch (_) {
      _showMessage('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _routeByRole(String uid) async {
    final restaurantDoc =
        await _firestore.collection('restaurants').doc(uid).get();
    if (restaurantDoc.exists && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RestaurantShell()),
      );
      return;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (userDoc.exists && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerShell()),
      );
      return;
    }

    // Auth user exists (verified) but Firestore profile missing — e.g. signup
    // didn’t finish after email verification. Offer recovery instead of a dead-end toast.
    if (mounted) {
      await _recoverMissingFirestoreProfile(uid);
    }
  }

  /// Creates a minimal [users] or [restaurants] doc so routing can proceed.
  Future<void> _recoverMissingFirestoreProfile(String uid) async {
    final authUser = _auth.currentUser;
    if (authUser == null || !mounted) return;

    // Sign-in already succeeded; hide the login spinner while the user chooses a role.
    if (mounted) setState(() => _loading = false);

    final choice = await showDialog<AccountRole?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => material.AlertDialog(
        title: const material.Text('Finish account setup'),
        content: const material.Text(
          'You’re signed in, but your app profile wasn’t found. '
          'This can happen if setup didn’t complete after email verification. '
          'Choose how you use Speak Dine to create your profile and continue.',
        ),
        actions: [
          material.TextButton(
            onPressed: () => Navigator.pop(ctx, AccountRole.customer),
            child: const material.Text('Customer'),
          ),
          material.TextButton(
            onPressed: () => Navigator.pop(ctx, AccountRole.restaurant),
            child: const material.Text('Restaurant'),
          ),
          material.TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const material.Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) {
      await _auth.signOut();
      return;
    }

    final email = (authUser.email ?? '').trim();
    if (email.isEmpty) {
      _showMessage('Your account has no email on file. Please contact support.');
      await _auth.signOut();
      return;
    }

    setState(() => _loading = true);
    try {
      if (choice == AccountRole.restaurant) {
        var restaurantName =
            'venue_${uid.replaceAll('-', '').substring(0, 12)}';
        var res = await LoginLookupSync.syncRestaurantName(
          firestore: _firestore,
          uid: uid,
          email: email,
          previousName: null,
          newName: restaurantName,
        );
        if (res == LoginLookupSyncResult.nameAlreadyClaimed) {
          restaurantName = 'venue_${uid.replaceAll('-', '')}';
          res = await LoginLookupSync.syncRestaurantName(
            firestore: _firestore,
            uid: uid,
            email: email,
            previousName: null,
            newName: restaurantName,
          );
        }
        if (res != LoginLookupSyncResult.success) {
          _showMessage(
            res == LoginLookupSyncResult.failed
                ? 'Network error. Check your connection and try again.'
                : 'Could not reserve a sign-in name. Try again in a moment.',
          );
          await _auth.signOut();
          return;
        }
        await _firestore.collection('restaurants').doc(uid).set({
          'uid': uid,
          'restaurantName': restaurantName,
          'signInRestaurantName': restaurantName,
          'email': email,
          'phone': '',
          'address': '',
          'city': '',
          'restaurantCategory': 'other',
          'role': 'restaurant',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        var customerName = 'user_${uid.replaceAll('-', '').substring(0, 12)}';
        var res = await LoginLookupSync.syncCustomerDisplayName(
          firestore: _firestore,
          uid: uid,
          email: email,
          previousName: null,
          newName: customerName,
        );
        if (res == LoginLookupSyncResult.nameAlreadyClaimed) {
          customerName = 'user_${uid.replaceAll('-', '')}';
          res = await LoginLookupSync.syncCustomerDisplayName(
            firestore: _firestore,
            uid: uid,
            email: email,
            previousName: null,
            newName: customerName,
          );
        }
        if (res != LoginLookupSyncResult.success) {
          _showMessage(
            res == LoginLookupSyncResult.failed
                ? 'Network error. Check your connection and try again.'
                : 'Could not reserve a sign-in name. Try again in a moment.',
          );
          await _auth.signOut();
          return;
        }
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'name': customerName,
          'email': email,
          'phone': '',
          'city': '',
          'role': 'customer',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      await _routeByRole(uid);
    } catch (_) {
      _showMessage('Could not finish setup. Please try again.');
      await _auth.signOut();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again later.';
      default:
        return 'Unable to sign in. Please try again.';
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showAppToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/splash.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          KeyboardFriendlyScrollBody(
            child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/speakdine_logo.png',
                      width: 96,
                      height: 96,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 380,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.border
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: const Text('Sign in to continue')
                                .muted()
                                .small(),
                          ),
                          const SizedBox(height: 20),
                          AuthLabeledTextField(
                            label: 'Email',
                            controller: _identifierController,
                            placeholder: 'you@example.com',
                          ),
                          AuthLabeledTextField(
                            label: 'Password',
                            controller: _passwordController,
                            placeholder: 'Enter your password',
                            obscure: true,
                          ),
                          const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ForgotPasswordView(),
                                ),
                              );
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _loading
                            ? Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              )
                            : PrimaryButton(
                                onPressed: _login,
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(RadixIcons.enter, size: 16),
                                    SizedBox(width: 8),
                                    Text('Login'),
                                  ],
                                ),
                              ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'or sign in with',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlineButton(
                            onPressed: _loading ? null : _handleGoogleSignIn,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const GoogleLogoMark(size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignupView(),
                            ),
                          );
                        },
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
            ),
          ),
        ],
      ),
    );
  }
}

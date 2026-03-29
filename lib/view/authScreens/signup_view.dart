import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speak_dine/utils/customer_username_validation.dart';
import 'package:speak_dine/utils/password_strength.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/widgets/auth_labeled_text_field.dart';
import 'package:speak_dine/widgets/password_strength_indicator.dart';
import 'package:speak_dine/services/google_auth_service.dart';
import 'package:speak_dine/view/home/customer_shell.dart';
import 'package:speak_dine/view/home/restaurant_shell.dart';
import 'package:speak_dine/widgets/sd_lib_restaurant_category_picker.dart';
import 'package:speak_dine/utils/google_sign_in_guard.dart';
import 'package:speak_dine/services/login_lookup_sync.dart';
import 'package:speak_dine/widgets/google_logo_mark.dart';
import 'package:speak_dine/widgets/keyboard_friendly.dart';

enum AccountRole { customer, restaurant }

class SignupView extends StatefulWidget {
  const SignupView({super.key});

  @override
  State<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<SignupView> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Shown after Firebase redirects from the verification link (see [web/email_verified.html]).
  static const String _emailVerificationContinueUrl =
      'https://speakdine-8f4e9.web.app/email_verified.html';

  AccountRole _selectedRole = AccountRole.customer;
  bool _loading = false;
  bool _awaitingEmailVerification = false;
  bool _emailVerifiedDetected = false;
  Timer? _emailVerificationPollTimer;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  /// SD-lib restaurant type (required for [AccountRole.restaurant]).
  String? _restaurantCategoryId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopEmailVerificationPolling();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _awaitingEmailVerification) {
      unawaited(_syncEmailVerificationFromServer());
    }
  }

  void _stopEmailVerificationPolling() {
    _emailVerificationPollTimer?.cancel();
    _emailVerificationPollTimer = null;
  }

  void _startEmailVerificationPolling() {
    _stopEmailVerificationPolling();
    unawaited(_syncEmailVerificationFromServer());
    _emailVerificationPollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_syncEmailVerificationFromServer());
    });
  }

  Future<void> _syncEmailVerificationFromServer() async {
    if (!mounted || !_awaitingEmailVerification) return;
    try {
      final before = _auth.currentUser;
      if (before == null) return;
      await before.reload();
      final after = _auth.currentUser;
      if (!mounted || after == null) return;
      if (after.emailVerified) {
        await after.getIdToken(true);
        if (!mounted) return;
        setState(() => _emailVerifiedDetected = true);
        _stopEmailVerificationPolling();
      }
    } catch (_) {
      // Ignore transient network errors while polling.
    }
  }

  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return _selectedRole == AccountRole.customer
          ? 'Please enter your name'
          : 'Please enter restaurant name';
    }
    if (_nameController.text.trim().length < 3) {
      return 'Name must be at least 3 characters';
    }
    if (_selectedRole == AccountRole.customer) {
      final uErr = validateCustomerUsernameFormat(_nameController.text);
      if (uErr != null) return uErr;
    }
    if (_emailController.text.trim().isEmpty) return 'Please enter email';
    if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$')
        .hasMatch(_emailController.text.trim())) {
      return 'Please enter a valid email';
    }
    if (_phoneController.text.trim().isEmpty) {
      return 'Please enter phone number';
    }
    if (_phoneController.text.trim().length < 10) {
      return 'Enter a valid phone number';
    }
    if (_cityController.text.trim().isEmpty) {
      return 'Please enter your city';
    }
    if (_cityController.text.trim().length < 2) {
      return 'City name is too short';
    }
    if (_selectedRole == AccountRole.restaurant &&
        _addressController.text.trim().isEmpty) {
      return 'Please enter address';
    }
    if (_selectedRole == AccountRole.restaurant &&
        (_restaurantCategoryId == null || _restaurantCategoryId!.isEmpty)) {
      return 'Please select a restaurant category';
    }
    final strengthError =
        validatePasswordStrength(_passwordController.text.trim());
    if (strengthError != null) return strengthError;
    if (_confirmPasswordController.text != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _register() async {
    final error = _validate();
    if (error != null) {
      _showMessage(error);
      return;
    }

    try {
      setState(() => _loading = true);

      final credential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = credential.user;
      if (user == null) {
        _showMessage('Registration failed. Please try again.');
        return;
      }

      final uid = user.uid;

      // Block only real name collisions (another venue/customer still has a profile). Stale
      // [loginLookup] rows from deleted accounts are ignored here and reclaimed on verify.
      if (_selectedRole == AccountRole.restaurant) {
        final taken = await LoginLookupSync.isRestaurantNameInUseByAnotherVenue(
          _firestore,
          _nameController.text.trim(),
          uid,
        );
        if (taken) {
          try {
            await user.delete();
          } catch (_) {
            // Rare; Auth user may need manual cleanup in console.
          }
          _showMessage(
            'This restaurant name is already used for sign-in. Choose a different name.',
          );
          return;
        }
      } else {
        final taken =
            await LoginLookupSync.isCustomerUsernameInUseByAnotherAccount(
          _firestore,
          _nameController.text.trim(),
          uid,
        );
        if (taken) {
          try {
            await user.delete();
          } catch (_) {
            // Rare; Auth user may need manual cleanup in console.
          }
          _showMessage(
            'This username is already taken. Choose a different one.',
          );
          return;
        }
      }

      // 1) Create the Firebase Auth user.
      // 2) Send email verification link (continue page has “Open Speak Dine” — see web/email_verified.html).
      // 3) Only after verification we write Firestore profile data.
      try {
        await user.sendEmailVerification(
          ActionCodeSettings(
            url: _emailVerificationContinueUrl,
            handleCodeInApp: false,
            androidPackageName: 'com.example.speak_dine',
            androidMinimumVersion: '1',
          ),
        );
      } catch (_) {
        // Custom continue URL requires hosting + authorized domain; fall back to default email.
        await user.sendEmailVerification();
      }

      if (!mounted) return;
      setState(() {
        _awaitingEmailVerification = true;
        _emailVerifiedDetected = false;
      });
      _startEmailVerificationPolling();
      _showMessage(
        'Verification email sent. Open the link, then tap Open Speak Dine on the web page.',
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Unable to create account. Please try again.';
      if (e.code == 'weak-password') {
        message = 'Password is too weak. Please use a stronger one.';
      } else if (e.code == 'email-already-in-use') {
        message = 'An account already exists with this email.';
      } else if (e.code == 'invalid-email') {
        message = 'Please enter a valid email address.';
      }
      _showMessage(message);
    } catch (_) {
      _showMessage('Something went wrong. Please wait and try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showAppToast(context, message);
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

    if (mounted) {
      _showMessage('Account not found. Please login again.');
      await _auth.signOut();
    }
  }

  Future<void> _handleGoogleSignUp() async {
    if (_loading) return;
    if (isGoogleSignInMissingAndroidWebClientId) {
      _showMessage(googleSignInMissingWebClientIdMessage);
      return;
    }
    setState(() => _loading = true);
    try {
      final routeType =
          await GoogleAuthService().signInWithGoogleAndUpsert(
        defaultCustomer: true,
      );
      if (routeType == null) return;

      final user = _auth.currentUser;
      if (user == null) {
        _showMessage('Login failed');
        return;
      }

      // If Google didn't mark email as verified for some reason, block navigation.
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

  Future<void> _completeSignupAfterEmailVerification() async {
    setState(() => _loading = true);
    try {
      User? user = _auth.currentUser;
      if (user == null) {
        _showMessage('Please start signup again.');
        return;
      }

      // Firebase may take a moment to flip emailVerified after the link is opened; refresh token too.
      for (var attempt = 0; attempt < 10; attempt++) {
        final u = _auth.currentUser;
        if (u == null) {
          _showMessage('Please start signup again.');
          return;
        }
        await u.reload();
        user = _auth.currentUser;
        if (user == null) {
          _showMessage('Please start signup again.');
          return;
        }
        if (user.emailVerified) break;
        if (attempt < 9) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }

      user = _auth.currentUser;
      if (user == null || !user.emailVerified) {
        _showMessage(
          'Email not verified yet. Open the link in your email, wait until this screen shows verified, then try again.',
        );
        return;
      }

      await user.getIdToken(true);

      final uid = user.uid;

      if (_selectedRole == AccountRole.customer) {
        final name = _nameController.text.trim();
        final emailAddr = _emailController.text.trim();
        final lookupRes = await LoginLookupSync.syncCustomerDisplayName(
          firestore: _firestore,
          uid: uid,
          email: emailAddr,
          previousName: null,
          newName: name,
        );
        if (lookupRes == LoginLookupSyncResult.nameAlreadyClaimed) {
          _showMessage(
            'That username was taken while you verified email. Change it and tap Continue again.',
          );
          return;
        }
        if (lookupRes == LoginLookupSyncResult.failed) {
          _showMessage(
            'Could not save your username. Check your connection and tap Continue again.',
          );
          return;
        }
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'name': name,
          'email': emailAddr,
          'phone': _phoneController.text.trim(),
          'city': _cityController.text.trim(),
          'role': 'customer',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        final rName = _nameController.text.trim();
        final emailAddr = _emailController.text.trim();
        final lookupRes = await LoginLookupSync.syncRestaurantName(
          firestore: _firestore,
          uid: uid,
          email: emailAddr,
          previousName: null,
          newName: rName,
        );
        if (lookupRes == LoginLookupSyncResult.nameAlreadyClaimed) {
          _showMessage(
            'That restaurant name was taken while you verified email. Change it and tap Continue again.',
          );
          return;
        }
        if (lookupRes == LoginLookupSyncResult.failed) {
          _showMessage(
            'Could not save your restaurant name. Check your connection and tap Continue again.',
          );
          return;
        }
        await _firestore.collection('restaurants').doc(uid).set({
          'uid': uid,
          'restaurantName': rName,
          'signInRestaurantName': rName,
          'email': emailAddr,
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'city': _cityController.text.trim(),
          'restaurantCategory': _restaurantCategoryId ?? 'other',
          'role': 'restaurant',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      _stopEmailVerificationPolling();
      _showMessage('Registered successfully! Please login.');
      await _auth.signOut();
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Verification failed. Please try again.');
    } catch (e) {
      _showMessage('Verification failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildEmailVerificationStep(ThemeData theme) {
    final email = _emailController.text.trim();
    final pink = theme.colorScheme.primary;
    return Container(
      width: 380,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verify your email',
            style: TextStyle(
              color: pink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            email.isNotEmpty
                ? 'We sent a verification link to $email.'
                : 'We sent a verification link to your email.',
            style: TextStyle(
              color: pink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Open your email, tap the verification link, then on the web page tap “Open Speak Dine” (or return to this app). When your email shows as verified below, tap the button to finish.',
            style: TextStyle(
              color: pink.withValues(alpha: 0.92),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_emailVerifiedDetected) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    RadixIcons.checkCircled,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Email verified. You can tap below to complete registration.',
                      style: TextStyle(
                        color: pink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _loading
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
                    onPressed: _completeSignupAfterEmailVerification,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(RadixIcons.checkCircled, size: 16),
                        SizedBox(width: 8),
                        Text('I have verified my email'),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlineButton(
              onPressed: () async {
                _stopEmailVerificationPolling();
                await _auth.signOut();
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: Text(
                'Back to login',
                style: TextStyle(
                  color: pink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRestaurant = _selectedRole == AccountRole.restaurant;

    if (_awaitingEmailVerification) {
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
              alignment: Alignment.center,
              child: _buildEmailVerificationStep(theme),
            ),
          ],
        ),
      );
    }

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
            alignment: Alignment.topCenter,
            child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/speakdine_logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Create Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 380,
                      constraints: const BoxConstraints(maxHeight: 720),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.border
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child:
                                const Text('Fill in the details to get started')
                                    .muted()
                                    .small(),
                          ),
                          const SizedBox(height: 16),
                          _buildRoleToggle(theme),
                          const SizedBox(height: 20),
                        AuthLabeledTextField(
                          label: isRestaurant ? 'Restaurant Name' : 'Full Name',
                          controller: _nameController,
                          placeholder: isRestaurant
                              ? 'My Restaurant'
                              : 'e.g. jane_doe (lowercase, no spaces)',
                        ),
                        AuthLabeledTextField(
                          label: 'Email',
                          controller: _emailController,
                          placeholder: 'you@example.com',
                        ),
                        AuthLabeledTextField(
                          label: 'Phone',
                          controller: _phoneController,
                          placeholder: '+1 234 567 8900',
                        ),
                        AuthLabeledTextField(
                          label: 'City',
                          controller: _cityController,
                          placeholder: isRestaurant
                              ? 'City where the restaurant is located'
                              : 'Your city (e.g. Lahore)',
                        ),
                        if (isRestaurant)
                          AuthLabeledTextField(
                            label: 'Address',
                            controller: _addressController,
                            placeholder: '123 Main St, City',
                          ),
                        if (isRestaurant) ...[
                          const SizedBox(height: 16),
                          SdLibRestaurantCategoryPicker(
                            theme: theme,
                            selectedId: _restaurantCategoryId,
                            onChanged: (id) =>
                                setState(() => _restaurantCategoryId = id),
                          ),
                        ],
                        AuthLabeledTextField(
                          label: 'Password',
                          controller: _passwordController,
                          placeholder: 'At least 8 characters',
                          obscure: true,
                        ),
                        PasswordStrengthIndicator(controller: _passwordController),
                        AuthLabeledTextField(
                          label: 'Confirm Password',
                          controller: _confirmPasswordController,
                          placeholder: 'Re-enter password',
                          obscure: true,
                        ),
                        const SizedBox(height: 8),
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
                                onPressed: _register,
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(RadixIcons.plusCircled, size: 16),
                                    SizedBox(width: 8),
                                    Text('Register'),
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
                                'or sign up with',
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
                          onPressed: _loading ? null : _handleGoogleSignUp,
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
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text(
                          'Login',
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

  Widget _buildRoleToggle(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedRole = AccountRole.customer;
                _restaurantCategoryId = null;
                _addressController.clear();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedRole == AccountRole.customer
                      ? theme.colorScheme.background
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _selectedRole == AccountRole.customer
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.border
                                .withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(RadixIcons.person,
                        size: 14,
                        color: _selectedRole == AccountRole.customer
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground),
                    const SizedBox(width: 6),
                    Text(
                      'Customer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedRole == AccountRole.customer
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedRole = AccountRole.restaurant;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedRole == AccountRole.restaurant
                      ? theme.colorScheme.background
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _selectedRole == AccountRole.restaurant
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.border
                                .withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(RadixIcons.home,
                        size: 14,
                        color: _selectedRole == AccountRole.restaurant
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground),
                    const SizedBox(width: 6),
                    Text(
                      'Restaurant',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedRole == AccountRole.restaurant
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

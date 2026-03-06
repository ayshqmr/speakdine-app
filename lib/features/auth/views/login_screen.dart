import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:speakdine_app/core/theme/color_ext.dart';
import 'package:speakdine_app/services/auth_service.dart';
import 'package:speakdine_app/features/auth/views/signup_screen.dart';
import 'restaurant_registration_view.dart';
import 'package:speakdine_app/features/auth/views/forgot_password_screen.dart';
import 'package:speakdine_app/widgets/premium_snackbar.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _SignInViewState();
}

class _SignInViewState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/bg_light.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorExt.surface,
                      colorExt.primaryContainer.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Top Section - Logo (OUTSIDE THE CARD)
          Positioned(
            top: size.height * 0.08,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Logo
                Image.asset(
                  "assets/icons/speakdine_logo.png",
                  width: 120,
                  height: 120,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.restaurant_rounded,
                    size: 80,
                    color: colorExt.primary,
                  ),
                )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.0, 1.0), duration: 800.ms, curve: Curves.easeOutBack),

                const SizedBox(height: 20),

                // Welcome Text
                Text(
                  'Welcome Back',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: colorExt.primaryText,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                )
                .animate()
                .fadeIn(delay: 200.ms, duration: 600.ms)
                .slideY(begin: 0.2, end: 0, duration: 800.ms, curve: Curves.easeOutCubic),

                const SizedBox(height: 8),

                Text(
                  'Please sign in to continue your journey',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colorExt.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                )
                .animate()
                .fadeIn(delay: 400.ms, duration: 600.ms),
              ],
            ),
          ),

          // Glassmorphism Bottom Card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final shake = _shakeController.value;
                final offset = sin(shake * pi * 3) * 10 * (1 - shake);
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    constraints: BoxConstraints(
                      maxHeight: size.height * (MediaQuery.of(context).viewInsets.bottom > 0 ? 0.9 : 0.62),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(40),
                        topRight: Radius.circular(40),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 30,
                          offset: const Offset(0, -10),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      bottom: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Form Section
                            _UnifiedSignInForm(
                              key: const ValueKey("UnifiedForm"),
                              authService: _authService,
                              onSignUp: _showSignupBottomSheet,
                              onForgotPassword: () {
                                _showForgotPasswordBottomSheet();
                              },
                              onError: _triggerShake,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          .animate()
          .slideY(begin: 1.0, end: 0, duration: 800.ms, curve: Curves.easeOutQuart),
        ],
      ),
    );
  }

  void _showSignupBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildRoleSelectionSheet(
        title: "Join SpeakDine",
        subtitle: "How would you like to register?",
        onCustomerTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupScreen()));
        },
        onRestaurantTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (context) => const RestaurantRegistrationView()));
        },
      ),
    );
  }

  void _showForgotPasswordBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildRoleSelectionSheet(
        title: "Forgot Password",
        subtitle: "Which account needs recovery?",
        onCustomerTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (context) => const ForgotPasswordScreen(userType: 'customer')));
        },
        onRestaurantTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (context) => const ForgotPasswordScreen(userType: 'restaurant')));
        },
      ),
    );
  }

  Widget _buildRoleSelectionSheet({
    required String title,
    required String subtitle,
    required VoidCallback onCustomerTap,
    required VoidCallback onRestaurantTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -5))
        ]
      ),
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 5, decoration: BoxDecoration(color: colorExt.placeholder, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 24),
          Text(title, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
          const SizedBox(height: 8),
          Text(subtitle, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: colorExt.secondaryText)),
          const SizedBox(height: 32),
          _methodCard(
            title: "Customer",
            subtitle: "Order food and book tables",
            icon: Icons.person_rounded,
            onTap: onCustomerTap,
          ),
          const SizedBox(height: 16),
          _methodCard(
            title: "Restaurant",
            subtitle: "Manage your business",
            icon: Icons.restaurant_rounded,
            onTap: onRestaurantTap,
          ),
        ],
      ),
    );
  }

  Widget _methodCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorExt.primary.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(color: colorExt.primary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: colorExt.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: colorExt.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
                  Text(subtitle, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: colorExt.secondaryText)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colorExt.primary.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// Global Text Field Widget (Synced with ForgotPassword)
Widget _inputField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  String? hint,
  bool obscureText = false,
  Widget? suffix,
  String? Function(String?)? validator,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: const Color(0xff922052).withValues(alpha: 0.1),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: const Color(0xff3B1E2B),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.outfit(
          color: const Color(0xff6B5660),
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xff922052).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: const Color(0xff922052),
              size: 20,
            ),
          ),
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.transparent,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(
            color: Color(0xff922052),
            width: 1.5,
          ),
        ),
      ),
    ),
  );
}

class _UnifiedSignInForm extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;
  final VoidCallback onError;

  const _UnifiedSignInForm({
    super.key,
    required this.authService,
    required this.onSignUp,
    required this.onForgotPassword,
    required this.onError,
  });

  @override
  State<_UnifiedSignInForm> createState() => _UnifiedSignInFormState();
}

class _UnifiedSignInFormState extends State<_UnifiedSignInForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) {
      widget.onError();
      return;
    }

    setState(() => _isLoading = true);
    final result = await widget.authService.signInWithEmail(
      emailOrUsername: _emailController.text.trim(),
      password: _passwordController.text,
      userType: null, // Let the service auto-detect the user role
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['error'] != null) {
        widget.onError();
        PremiumSnackbar.show(context, message: result['error']!, isError: true);
      } else {
        if (result['type'] == 'restaurant') {
           Navigator.of(context).pushReplacementNamed('/restaurant-home');
        } else {
           Navigator.of(context).pushReplacementNamed('/customer-home');
        }
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    final result = await widget.authService.signInWithGoogle(userType: null);

    if (mounted) {
      if (result['error'] != null) {
        widget.onError();
        PremiumSnackbar.show(context, message: result['error']!, isError: true);
        setState(() => _isLoading = false);
      } else {
        if (result['type'] == 'restaurant') {
           Navigator.of(context).pushReplacementNamed('/restaurant-home');
        } else {
           Navigator.of(context).pushReplacementNamed('/customer-home');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _inputField(
            controller: _emailController,
            label: "Email or Username",
            icon: Icons.person_rounded,
            validator: (val) => val == null || val.isEmpty ? "Required" : null,
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 18),

          _inputField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            label: "Password",
            icon: Icons.password_rounded,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: const Color(0xff6B5660),
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (val) => val == null || val.isEmpty ? "Required" : null,
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onForgotPassword,
              child: Text(
                "Forgot Password?",
                style: GoogleFonts.outfit(
                  color: const Color(0xff922052),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleSignIn,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff922052),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 4,
                shadowColor: const Color(0xff922052).withValues(alpha: 0.3),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Text(
                      "SIGN IN",
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ).animate().fadeIn(delay: 300.ms).scale(begin: const Offset(0.95, 0.95)),

          const SizedBox(height: 24),

          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: const Color(0xffC4A4B4).withValues(alpha: 0.3), thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "or Sign in with",
                  style: GoogleFonts.outfit(
                    color: const Color(0xff6B5660),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(child: Divider(color: const Color(0xffC4A4B4).withValues(alpha: 0.3), thickness: 1)),
            ],
          )
          .animate()
          .fadeIn(delay: 350.ms),

          const SizedBox(height: 24),

          // Google Button
          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: _isLoading ? null : _handleGoogleSignIn,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xff3B1E2B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                side: BorderSide(
                  color: const Color(0xffC4A4B4).withValues(alpha: 0.3),
                  width: 1.5,
                ),
                elevation: 1,
                shadowColor: Colors.black.withValues(alpha: 0.1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    "assets/icons/google.png",
                    width: 24,
                    height: 24,
                    errorBuilder: (c, e, s) => Icon(Icons.g_mobiledata, size: 24, color: const Color(0xff922052)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Continue with Google",
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          )
          .animate()
          .fadeIn(delay: 400.ms)
          .scale(begin: const Offset(0.95, 0.95)),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Don't have an account? ",
                style: GoogleFonts.outfit(color: const Color(0xff6B5660)),
              ),
              GestureDetector(
                onTap: widget.onSignUp,
                child: Text(
                  "Create an account",
                  style: GoogleFonts.outfit(
                    color: const Color(0xff922052),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

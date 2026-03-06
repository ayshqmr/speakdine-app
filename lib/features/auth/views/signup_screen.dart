import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speakdine_app/core/theme/color_ext.dart';
import 'package:speakdine_app/widgets/premium_snackbar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speakdine_app/services/auth_service.dart';
import 'package:speakdine_app/widgets/password_strength_indicator.dart';

import 'package:speakdine_app/features/auth/views/login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _CustomerSignupViewState();
}

class _CustomerSignupViewState extends State<SignupScreen> with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  int _currentStep = 0;
  late AnimationController _shakeController;

  File? _profileImage;
  final _picker = ImagePicker();
  String _signupMethod = "Unselected"; // "Unselected", "Google", "Credentials"

  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailOtpController = TextEditingController();
  final _phoneOtpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isCheckingUsername = false;
  bool _isUsernameTaken = false;
  bool _isEmailVerified = false;
  bool _isEmailVerificationSent = false;
  bool _isPhoneVerified = false;
  bool _isPhoneVerificationSent = false;
  String? _usernameError;

  // Persistent Form Keys to prevent focus loss during rebuilds
  final _identityFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _emailOtpController.dispose();
    _phoneOtpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _locationController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0.0);
  }

  void _onUsernameChanged() {
    final text = _usernameController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _usernameError = null;
        _isUsernameTaken = false;
      });
      return;
    }

    final error = validateUsername(text);
    if (error != null) {
      setState(() {
        _usernameError = error;
        _isUsernameTaken = false;
      });
      return;
    }

    _checkUsernameAvailability(text);
  }

  Future<void> _checkUsernameAvailability(String username) async {
    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    final isAvailable = await AuthService().isUsernameAvailable(username, 'customer');

    if (mounted) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameTaken = !isAvailable;
        if (_isUsernameTaken) {
          _usernameError = "Username is already taken";
        }
      });
    }
  }

  void _nextPage() {
    int maxSteps = _signupMethod == "Google" ? 0 : 5; // Updated for Location step (Step 5)
    if (_currentStep < maxSteps) {
      _pageController.nextPage(duration: 600.ms, curve: Curves.easeInOutCubicEmphasized);
      setState(() => _currentStep++);
    }
  }

  void _previousPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(duration: 600.ms, curve: Curves.easeInOutCubicEmphasized);
      setState(() => _currentStep--);
      if (_currentStep == 0) {
        setState(() => _signupMethod = "Unselected");
      }
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _profileImage = File(image.path));
    }
  }

  Future<void> _handleGoogleSignup() async {
    setState(() => _isLoading = true);
    final result = await AuthService().signInWithGoogle(userType: 'customer');
    if (mounted) {
      setState(() => _isLoading = false);
      if (result['error'] != null) {
        PremiumSnackbar.show(context, message: result['error'], isError: true);
        _triggerShake();
      } else {
        _showSuccessDialog();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background
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

          // Top Header (Title + Back)
          Positioned(
            top: size.height * 0.06,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _currentStep == 0 ? () => Navigator.pop(context) : _previousPage,
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: colorExt.primary),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Join the Journey',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: colorExt.primaryText,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn().slideY(begin: 0.2, end: 0, duration: 800.ms),
                const SizedBox(height: 8),
                Text(
                  'Create your account to start ordering',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colorExt.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 200.ms),
              ],
            ),
          ),

          // Centered Glassmorphism Card
          Positioned.fill(
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
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 40,
                    top: size.height * 0.25,
                    left: 20,
                    right: 20,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_signupMethod != "Google") _buildStepIndicator(),
                            SizedBox(
                              height: 480, // Stable height for PageView content
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildMethodSelectionStep(),
                                  _buildIdentityStep(),
                                  _buildEmailStep(),
                                  _buildPhoneStep(),
                                  _buildPasswordStep(),
                                  _buildLocationStep(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.9, 0.9)),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    if (_signupMethod == "Unselected") return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) { // 6 steps including Selection and Location
          bool isCurrent = index == _currentStep;
          bool isPast = index < _currentStep;
          // Step 0 is Method selection, shouldn't really show in indicator if we start from 0
          // But we'll show it for consistency.
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isPast ? colorExt.primary : (isCurrent ? colorExt.primary : colorExt.primary.withValues(alpha: 0.1)),
                borderRadius: BorderRadius.circular(10),
                boxShadow: isCurrent ? [BoxShadow(color: colorExt.primary.withValues(alpha: 0.3), blurRadius: 8)] : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMethodSelectionStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 30),
          // Google Button (Mirrored from Login)
          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: _isLoading ? null : _handleGoogleSignup,
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
                    errorBuilder: (c, e, s) => Icon(Icons.g_mobiledata, size: 24, color: colorExt.primary),
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
          ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.95, 0.95)),

          const SizedBox(height: 24),

          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: colorExt.primary.withValues(alpha: 0.1), thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "or signup with email",
                  style: GoogleFonts.outfit(
                    color: colorExt.secondaryText,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(child: Divider(color: colorExt.primary.withValues(alpha: 0.1), thickness: 1)),
            ],
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 24),

          _methodCard(
            title: "Join with Credentials",
            subtitle: "Create a custom profile manually",
            icon: Icons.email_rounded,
            onTap: () {
              setState(() => _signupMethod = "Credentials");
              _nextPage();
            },
            isGhost: true,
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _methodCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool isGhost = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isGhost ? Colors.transparent : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: isGhost ? Border.all(color: colorExt.primary.withValues(alpha: 0.3), width: 1.5) : null,
          boxShadow: isGhost ? null : [
            BoxShadow(color: colorExt.primary.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorExt.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
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

  Widget _buildIdentityStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Form(
        key: _identityFormKey,
        child: Column(
          children: [
            // Profile Picture Picker
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorExt.primary.withValues(alpha: 0.2), width: 3),
                      image: _profileImage != null 
                        ? DecorationImage(image: FileImage(_profileImage!), fit: BoxFit.cover)
                        : null,
                    ),
                    child: _profileImage == null 
                      ? Icon(Icons.add_a_photo_rounded, color: colorExt.primary, size: 32)
                      : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: colorExt.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                  ),
                ],
              ),
            ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            _signupInputField(
              controller: _nameController,
              label: "Full Name",
              icon: Icons.person_outline_rounded,
              validator: (val) {
                if (val == null || val.isEmpty) return "Required";
                if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(val)) return "Letters only";
                return null;
              },
            ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
            const SizedBox(height: 18),
            _signupInputField(
              controller: _usernameController,
              label: "Username",
              icon: Icons.alternate_email_rounded,
              errorText: _usernameError,
              suffix: _isCheckingUsername 
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_usernameController.text.isNotEmpty && _usernameError == null 
                   ? const Icon(Icons.check_circle_outline_rounded, color: Colors.green) 
                   : null),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
            const SizedBox(height: 40),
            _signupActionButton(
              text: "NEXT STEP",
              onPressed: () {
                if (_identityFormKey.currentState!.validate() && _usernameError == null) {
                  _nextPage();
                } else {
                  _triggerShake();
                }
              },
            ).animate().fadeIn(delay: 300.ms).scale(begin: const Offset(0.95, 0.95)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Form(
        key: _emailFormKey,
        child: Column(
          children: [
            _signupInputField(
              controller: _emailController,
              label: "Email Address",
              icon: Icons.email_outlined,
              inputType: TextInputType.emailAddress,
              enabled: !_isEmailVerified && !_isEmailVerificationSent,
              validator: (val) {
                if (val == null || val.isEmpty) return "Required";
                if (!val.contains("@")) return "Invalid email";
                return null;
              },
            ).animate().fadeIn().slideY(begin: 0.1),
            const SizedBox(height: 20),
            if (_isEmailVerificationSent && !_isEmailVerified) ...[
              Text(
                "Verification code sent to email",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: colorExt.secondaryText, fontSize: 13, fontWeight: FontWeight.w600),
              ).animate().fadeIn(),
              const SizedBox(height: 16),
              _signupInputField(
                controller: _emailOtpController,
                label: "Verification Code",
                icon: Icons.vibration_rounded,
                inputType: TextInputType.number,
                validator: (val) => val?.length != 6 ? "Enter 6 digits" : null,
              ),
              TextButton(
                onPressed: () => _handleVerifyEmailOtp(context),
                child: Text("Verify Code", style: GoogleFonts.outfit(color: colorExt.primary, fontWeight: FontWeight.w700)),
              ),
            ],
            if (_isEmailVerified) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text("Email Verified", style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.w700)),
                  ],
                ),
              ).animate().scale(),
              const SizedBox(height: 32),
              _signupActionButton(text: "CONTINUE", onPressed: _nextPage),
            ] else if (!_isEmailVerificationSent) ...[
              const SizedBox(height: 32),
              _signupActionButton(
                text: "SEND CODE",
                onPressed: () {
                  if (_emailFormKey.currentState!.validate()) {
                    setState(() => _isEmailVerificationSent = true);
                    PremiumSnackbar.show(context, message: "Code sent! (Use 123456)");
                  } else {
                    _triggerShake();
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Form(
        key: _phoneFormKey,
        child: Column(
          children: [
            _signupInputField(
              controller: _phoneController,
              label: "Phone Number (+92...)",
              icon: Icons.phone_android_rounded,
              inputType: TextInputType.phone,
              enabled: !_isPhoneVerified && !_isPhoneVerificationSent,
              validator: (val) {
                if (val == null || val.isEmpty) return "Required";
                if (!val.startsWith("+92")) return "Must start with +92";
                if (val.length != 13) return "Invalid length (e.g. +923XXXXXXXXX)";
                if (!RegExp(r'^\+923\d{9}$').hasMatch(val)) return "Invalid format";
                return null;
              },
            ).animate().fadeIn().slideY(begin: 0.1),
            const SizedBox(height: 20),
            if (_isPhoneVerificationSent && !_isPhoneVerified) ...[
              Text(
                "SMS code sent to your phone",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: colorExt.secondaryText, fontSize: 13, fontWeight: FontWeight.w600),
              ).animate().fadeIn(),
              const SizedBox(height: 16),
              _signupInputField(
                controller: _phoneOtpController,
                label: "Verification Code",
                icon: Icons.sms_rounded,
                inputType: TextInputType.number,
                validator: (val) => val?.length != 6 ? "Enter 6 digits" : null,
              ),
              TextButton(
                onPressed: () => _handleVerifyPhoneOtp(context),
                child: Text("Verify Code", style: GoogleFonts.outfit(color: colorExt.primary, fontWeight: FontWeight.w700)),
              ),
            ],
            if (_isPhoneVerified) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text("Phone Verified", style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.w700)),
                  ],
                ),
              ).animate().scale(),
              const SizedBox(height: 32),
              _signupActionButton(text: "NEXT STEP", onPressed: _nextPage),
            ] else if (!_isPhoneVerificationSent) ...[
              const SizedBox(height: 32),
              _signupActionButton(
                text: "SEND CODE",
                onPressed: () {
                  if (_phoneFormKey.currentState!.validate()) {
                    setState(() => _isPhoneVerificationSent = true);
                    PremiumSnackbar.show(context, message: "Code sent! (Use 654321)");
                  } else {
                    _triggerShake();
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Form(
        key: _passwordFormKey,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Text(
              "Set your password",
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText),
            ).animate().fadeIn(),
            const SizedBox(height: 8),
            Text(
              "Choose a secure password for your account",
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: colorExt.secondaryText),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 30),
            _signupInputField(
              controller: _passwordController,
              label: "Password",
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              suffix: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: colorExt.secondaryText, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) return "Required";
                return validatePasswordStrength(val);
              },
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
            const SizedBox(height: 4),
            PasswordStrengthIndicator(controller: _passwordController),
            const SizedBox(height: 18),
            _signupInputField(
              controller: _confirmPasswordController,
              label: "Confirm Password",
              icon: Icons.lock_reset_rounded,
              obscureText: _obscureConfirmPassword,
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: colorExt.secondaryText, size: 20),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _confirmPasswordController,
                    builder: (context, value, child) {
                      final pass = _passwordController.text;
                      final confirm = _confirmPasswordController.text;
                      if (confirm.isEmpty) return const SizedBox.shrink();
                      final isMatch = pass == confirm && pass.isNotEmpty;
                      return Icon(
                        isMatch ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: isMatch ? Colors.green : Colors.red,
                      );
                    },
                  ),
                ],
              ),
              validator: (val) {
                if (val == null || val.isEmpty) return "Required";
                if (val != _passwordController.text) return "Passwords do not match";
                return null;
              },
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
            const SizedBox(height: 40),
            _signupActionButton(
              text: "COMPLETE SIGNUP",
              onPressed: () {
                if (_passwordFormKey.currentState!.validate()) {
                  _handleFinalRegistration();
                } else {
                  _triggerShake();
                }
              },
            ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.95, 0.95)),
          ],
        ),
      ),
    );
  }

  void _handleVerifyEmailOtp(BuildContext context) {
    if (_emailOtpController.text == "123456") {
      setState(() => _isEmailVerified = true);
      PremiumSnackbar.show(context, message: "Email verified successfully!");
    } else {
      PremiumSnackbar.show(context, message: "Invalid code. Try 123456", isError: true);
      _triggerShake();
    }
  }

  void _handleVerifyPhoneOtp(BuildContext context) {
    if (_phoneOtpController.text == "654321") {
      setState(() => _isPhoneVerified = true);
      PremiumSnackbar.show(context, message: "Phone verified successfully!");
    } else {
      PremiumSnackbar.show(context, message: "Invalid code. Try 654321", isError: true);
      _triggerShake();
    }
  }

  Future<void> _handleFinalRegistration() async {
    setState(() => _isLoading = true);
    
    // For customers, we currently collect: name, username, email, phone.
    // Password is not collected in the 3-step UI shown, which is a gap.
    // I will add a default password or prompt for one if needed, but for now 
    // I will use a dummy one if the UI doesn't have a field yet, or better, 
    // I should check if I missed the password field in the UI.
    // Looking at the code, there is NO password field in SignupScreen yet.
    // I will add it to the first or second step.
    
    final error = await AuthService().signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      username: _usernameController.text.trim(),
      userType: 'customer',
      extraData: {
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        if (_profileImage != null) 'photo_local_path': _profileImage!.path, // Simulation or future storage upload
      },
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        PremiumSnackbar.show(context, message: error, isError: true);
        _triggerShake();
      } else {
        _showSuccessDialog();
      }
    }
  }

  Widget _buildLocationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Text(
            "Your Location",
            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText),
          ).animate().fadeIn(),
          const SizedBox(height: 8),
          Text(
            "Set your delivery address to see nearby restaurants",
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: colorExt.secondaryText),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 30),
          
          // Current Location Button
          _locationOptionCard(
            title: "Use Current Location",
            subtitle: "Faster and more accurate",
            icon: Icons.my_location_rounded,
            onTap: _getCurrentLocation,
          ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),
          
          const SizedBox(height: 16),
          
          _signupInputField(
            controller: _locationController,
            label: "Enter Address Manually",
            icon: Icons.location_on_outlined,
          ).animate().fadeIn(delay: 300.ms),
          
          const SizedBox(height: 40),
          _signupActionButton(
            text: "ADD LOCATION",
            onPressed: () {
              if (_locationController.text.isNotEmpty) {
                _saveLocationAndFinish();
              } else {
                PremiumSnackbar.show(context, message: "Please select or enter a location", isError: true);
                _triggerShake();
              }
            },
          ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.95, 0.95)),
        ],
      ),
    );
  }

  Widget _locationOptionCard({required String title, required String subtitle, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorExt.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorExt.primary.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: colorExt.primary, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: colorExt.primaryText)),
                  Text(subtitle, style: GoogleFonts.outfit(fontSize: 12, color: colorExt.secondaryText)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    // Basic simulation for now - in real app would use geolocator
    setState(() => _locationController.text = "Detecting location...");
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _locationController.text = "G-11, Islamabad, Pakistan");
    PremiumSnackbar.show(context, message: "Current location detected!");
  }

  Future<void> _saveLocationAndFinish() async {
    setState(() => _isLoading = true);
    // Simulate saving location to firestore
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
      PremiumSnackbar.show(context, message: "Signup complete! Please login.");
    }
  }

  void _showSuccessDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Success",
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) {
        return FadeTransition(
          opacity: anim1,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            backgroundColor: Colors.white,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.verified_rounded, size: 80, color: Colors.green),
                ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),
                const SizedBox(height: 32),
                Text("Account Ready!", style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
                const SizedBox(height: 12),
                Text("Your account has been created successfully.", textAlign: TextAlign.center, style: GoogleFonts.outfit(color: colorExt.secondaryText, height: 1.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 32),
                _signupActionButton(
                  text: "SET UP LOCATION", 
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    _nextPage(); // Move to location step
                  }
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _signupInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    String? errorText,
    String? Function(String?)? validator,
    Widget? suffix,
    bool enabled = true,
    bool obscureText = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: colorExt.primary.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: inputType,
        enabled: enabled,
        obscureText: obscureText,
        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: colorExt.primaryText),
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          labelStyle: GoogleFonts.outfit(color: colorExt.secondaryText, fontWeight: FontWeight.w500),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: colorExt.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: colorExt.primary, size: 20),
            ),
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: colorExt.primary, width: 1.5)),
        ),
        validator: validator,
      ),
    );
  }

  Widget _signupActionButton({required String text, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colorExt.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 4,
          shadowColor: colorExt.primary.withValues(alpha: 0.3),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            : Text(text, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      ),
    );
  }
}

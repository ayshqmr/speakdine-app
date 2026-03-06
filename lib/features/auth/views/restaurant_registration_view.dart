import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pinput/pinput.dart';
import 'package:speakdine_app/services/auth_service.dart';
import 'package:speakdine_app/core/theme/color_ext.dart';
import 'package:speakdine_app/features/auth/views/login_screen.dart';
import 'package:speakdine_app/models/restaurant_model.dart';
import 'package:speakdine_app/core/utils/pakistani_locations.dart';
import 'package:speakdine_app/widgets/premium_snackbar.dart';
import 'package:speakdine_app/widgets/time_picker_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speakdine_app/widgets/password_strength_indicator.dart';

class RestaurantRegistrationView extends StatefulWidget {
  const RestaurantRegistrationView({super.key});

  @override
  State<RestaurantRegistrationView> createState() => _RestaurantRegistrationViewState();
}

class _RestaurantRegistrationViewState extends State<RestaurantRegistrationView> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  final _authService = AuthService();
  late AnimationController _shakeController;
  
  // Controllers
  final _restaurantNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpEmailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _landlineController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  // Address Controllers
  final _streetNumberController = TextEditingController();
  final _floorNumberController = TextEditingController();
  final _zipCodeController = TextEditingController();

  int _currentStep = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  File? _profilePicture;
  
  String? _selectedProvince;
  String? _selectedCity;
  
  final Map<String, OpeningHours> _openingHours = {
    'Monday': OpeningHours(openTime: '10:00 AM', closeTime: '10:00 PM'),
    'Tuesday': OpeningHours(openTime: '10:00 AM', closeTime: '10:00 PM'),
    'Wednesday': OpeningHours(openTime: '10:00 AM', closeTime: '10:00 PM'),
    'Thursday': OpeningHours(openTime: '10:00 AM', closeTime: '10:00 PM'),
    'Friday': OpeningHours(openTime: '10:00 AM', closeTime: '10:00 PM'),
    'Saturday': OpeningHours(openTime: '10:00 AM', closeTime: '10:00 PM'),
    'Sunday': OpeningHours(openTime: '10:00 AM', closeTime: '10:00 PM'),
  };

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
    _pageController.dispose();
    _restaurantNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpEmailController.dispose();
    _phoneController.dispose();
    _landlineController.dispose();
    _descriptionController.dispose();
    _streetNumberController.dispose();
    _floorNumberController.dispose();
    _zipCodeController.dispose();
    _confirmPasswordController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0.0);
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _profilePicture = File(image.path));
    }
  }

  void _nextStep() {
    if (_currentStep == 0) { // Identity
      if (_restaurantNameController.text.isEmpty || _usernameController.text.isEmpty) {
        PremiumSnackbar.show(context, message: "Please fill all required fields", isError: true);
        _triggerShake();
        return;
      }
      final userError = validateUsername(_usernameController.text);
      if (userError != null) {
        PremiumSnackbar.show(context, message: userError, isError: true);
        _triggerShake();
        return;
      }
    } else if (_currentStep == 1) { // Credentials
      if (_emailController.text.isEmpty || !_authService.isValidEmail(_emailController.text)) {
        PremiumSnackbar.show(context, message: "Enter a valid email", isError: true);
        _triggerShake();
        return;
      }
    } else if (_currentStep == 3) { // Contact
       final phone = _phoneController.text.trim();
       if (phone.isEmpty || !phone.startsWith("+92") || phone.length != 13 || !RegExp(r'^\+923\d{9}$').hasMatch(phone)) {
         PremiumSnackbar.show(context, message: "Enter a valid phone number (e.g. +923XXXXXXXXX)", isError: true);
         _triggerShake();
         return;
       }
    } else if (_currentStep == 4) { // Address
       if (_selectedProvince == null || _selectedCity == null || _streetNumberController.text.isEmpty) {
         PremiumSnackbar.show(context, message: "Enter complete address details", isError: true);
         _triggerShake();
         return;
       }
    } else if (_currentStep == 6) { // Set Password
      final strengthError = validatePasswordStrength(_passwordController.text);
      if (strengthError != null) {
        PremiumSnackbar.show(context, message: strengthError, isError: true);
        _triggerShake();
        return;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        PremiumSnackbar.show(context, message: "Passwords do not match", isError: true);
        _triggerShake();
        return;
      }
    } else if (_currentStep == 7) { // Success screen transition
      _finalizeSignup();
      return; // Prevent incrementing step further
    }
    
    _pageController.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubicEmphasized);
    setState(() => _currentStep++);
  }

  Future<void> _finalizeSignup() async {
    setState(() => _isLoading = true);
    
    final Map<String, dynamic> extraData = {
      'restaurant_name': _restaurantNameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'landline': _landlineController.text.trim(),
      'description': _descriptionController.text.trim(),
      'address': {
        'province': _selectedProvince,
        'city': _selectedCity,
        'street': _streetNumberController.text.trim(),
        'floor': _floorNumberController.text.trim(),
        'zip_code': _zipCodeController.text.trim(),
      },
      'opening_hours': _openingHours.map((key, value) => MapEntry(key, {
        'open': value.openTime,
        'close': value.closeTime,
      })),
      'status': 'pending', 
    };

    final error = await _authService.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      username: _usernameController.text.trim(),
      userType: 'restaurant',
      extraData: extraData,
    );

    setState(() => _isLoading = false);
    
    if (error != null) {
      PremiumSnackbar.show(context, message: error, isError: true);
      _triggerShake();
      setState(() => _currentStep = 1);
      _pageController.animateToPage(1, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubicEmphasized);
      return;
    }

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      });
    }
  }

  void _previousStep() {
    _pageController.previousPage(duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubicEmphasized);
    setState(() => _currentStep--);
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

          // Top Header
          Positioned(
            top: size.height * 0.06,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () {
                        if (_currentStep == 0) {
                          Navigator.pop(context);
                        } else if (_currentStep < 7) { // Adjusted for new step count
                          _previousStep();
                        }
                      },
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: colorExt.primary),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Partner with SpeakDine',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: colorExt.primaryText,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn().slideY(begin: 0.2, end: 0, duration: 800.ms),
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
                    top: size.height * 0.2,
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
                            _buildStepsIndicator(),
                            SizedBox(
                              height: 480, // Stable height for PageView content
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildStep0Identity(),
                                  _buildStep1Credentials(), // Email only
                                  _buildStep2EmailVerification(),
                                  _buildStep3Contact(),
                                  _buildStep4Address(),
                                  _buildStep5Hours(),
                                  _buildStep6Password(), // New step for password
                                  _buildStep7Success(), // Renamed
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

  Widget _buildStepsIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(8, (index) { // Changed from 7 to 8 steps
          bool isCurrent = index == _currentStep;
          bool isPast = index < _currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isPast ? colorExt.primary : (isCurrent ? colorExt.primary : colorExt.primary.withValues(alpha: 0.1)),
                borderRadius: BorderRadius.circular(10),
                boxShadow: isCurrent ? [BoxShadow(color: colorExt.primary.withValues(alpha: 0.3), blurRadius: 8)] : null,
              ),
            ),
          );
        }),
      ),
    ).animate().fadeIn().slideY(begin: -1, end: 0);
  }

  Widget _buildStep0Identity() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      child: Column(
        children: [
          Text("Grow with Us", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: colorExt.primary, width: 2),
                boxShadow: [BoxShadow(color: colorExt.primary.withValues(alpha: 0.1), blurRadius: 15)],
              ),
              child: _profilePicture == null 
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, color: colorExt.primary, size: 28),
                      const SizedBox(height: 4),
                      Text("LOGO", style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: colorExt.primary, letterSpacing: 1)),
                    ],
                  )
                : ClipOval(child: Image.file(_profilePicture!, fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 24),
          _regInputField(_restaurantNameController, "Restaurant Name", Icons.restaurant_rounded),
          const SizedBox(height: 16),
          _regInputField(_usernameController, "Admin Username", Icons.person_rounded),
          const SizedBox(height: 40),
          _regActionButton("GET STARTED", _nextStep),
        ],
      ),
    );
  }

  Widget _buildStep1Credentials() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      child: Column(
        children: [
          Text("Business Login", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
          const SizedBox(height: 32),
          _regInputField(_emailController, "Business Email", Icons.email_rounded, isEmail: true),
          const SizedBox(height: 40),
          _regActionButton("CONTINUE", _nextStep),
        ],
      ),
    );
  }

  Widget _buildStep2EmailVerification() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: colorExt.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.mark_email_unread_rounded, size: 50, color: colorExt.primary),
          ),
          const SizedBox(height: 24),
          Text("Verify Email", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
          const SizedBox(height: 12),
          Text("Checking ownership of\n${_emailController.text}", textAlign: TextAlign.center, style: GoogleFonts.outfit(color: colorExt.secondaryText, height: 1.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 40),
          Pinput(
            controller: _otpEmailController,
            length: 6,
            onCompleted: (_) => _nextStep(),
            defaultPinTheme: _pinputTheme(),
          ),
          const SizedBox(height: 32),
          _regActionButton("VERIFY BUSINESS", _nextStep),
        ],
      ),
    );
  }

  Widget _buildStep3Contact() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      child: Column(
        children: [
          Text("Company Contact", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
          const SizedBox(height: 32),
          _regInputField(_phoneController, "Official Mobile (+92...)", Icons.phone_android_rounded),
          const SizedBox(height: 16),
          _regInputField(_landlineController, "Landline (Optional)", Icons.phone_rounded),
          const SizedBox(height: 16),
          _regInputField(_descriptionController, "Restaurant Bio", Icons.info_rounded, maxLines: 3),
          const SizedBox(height: 40),
          _regActionButton("CONTINUE", _nextStep),
        ],
      ),
    );
  }

  Widget _buildStep4Address() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      child: Column(
        children: [
          Text("Store Location", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
          const SizedBox(height: 32),
          _regDropdownField("Province", _selectedProvince, PakistaniLocations.getProvinces(), Icons.map_rounded, (v) {
            setState(() {
              _selectedProvince = v;
              _selectedCity = null;
            });
          }),
          const SizedBox(height: 16),
          _regDropdownField("City", _selectedCity, _selectedProvince == null ? [] : PakistaniLocations.getCitiesForProvince(_selectedProvince!), Icons.location_city_rounded, (v) {
            setState(() => _selectedCity = v);
          }),
          const SizedBox(height: 16),
          _regInputField(_streetNumberController, "Full Street Address", Icons.location_on_rounded),
          const SizedBox(height: 40),
          _regActionButton("CONTINUE", _nextStep),
        ],
      ),
    );
  }

  Widget _buildStep5Hours() {
    return Column(
      children: [
        Text("Operating Hours", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            itemCount: _openingHours.length,
            separatorBuilder: (context, index) => Divider(color: colorExt.primary.withValues(alpha: 0.1), height: 1),
            itemBuilder: (context, index) {
              String day = _openingHours.keys.elementAt(index);
              OpeningHours hours = _openingHours[day]!;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(day, style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: colorExt.primaryText, fontSize: 16)),
                subtitle: Text("${hours.openTime} - ${hours.closeTime}", style: GoogleFonts.outfit(color: colorExt.secondaryText, fontWeight: FontWeight.w600, fontSize: 13)),
                trailing: IconButton.filledTonal(
                  onPressed: () => _showHoursDialog(day, hours),
                  icon: Icon(Icons.edit_rounded, size: 18, color: colorExt.primary),
                  style: IconButton.styleFrom(
                    backgroundColor: colorExt.primary.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _regActionButton("SUBMIT REGISTRATION", _nextStep),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _showHoursDialog(String day, OpeningHours hours) async {
    String openTime = hours.openTime;
    String closeTime = hours.closeTime;
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text("Edit $day Hours", style: GoogleFonts.outfit(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TimePickerWidget(
              label: "Opens at",
              selectedTime: openTime,
              onTimeSelected: (val) => openTime = val,
            ),
            const SizedBox(height: 16),
            TimePickerWidget(
              label: "Closes at",
              selectedTime: closeTime,
              onTimeSelected: (val) => closeTime = val,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("CANCEL", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: colorExt.secondaryText))),
          FilledButton(
            onPressed: () {
              setState(() => _openingHours[day] = OpeningHours(openTime: openTime, closeTime: closeTime));
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: colorExt.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            child: Text("SAVE", style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
          )
        ],
      ),
    );
  }

  Widget _buildStep6Password() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      child: Column(
        children: [
          Text("Secure Account", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
          const SizedBox(height: 32),
          _regPasswordField(_passwordController, "Set Password", isObscured: _obscurePassword, toggle: () => setState(() => _obscurePassword = !_obscurePassword)),
          const SizedBox(height: 8),
          PasswordStrengthIndicator(controller: _passwordController),
          const SizedBox(height: 16),
          _regPasswordField(_confirmPasswordController, "Confirm Password", isObscured: _obscureConfirmPassword, toggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword)),
          const SizedBox(height: 40),
          _regActionButton("FINALIZE REGISTRATION", _nextStep),
        ],
      ),
    );
  }

  Widget _buildStep7Success() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.verified_rounded, size: 80, color: Colors.green),
        ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),
        const SizedBox(height: 32),
        Text("Registration Sent!", style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: colorExt.primaryText)),
        const SizedBox(height: 12),
        Text("Your application is now under review.\nRedirecting to sign in...", textAlign: TextAlign.center, style: GoogleFonts.outfit(color: colorExt.secondaryText, height: 1.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _regInputField(TextEditingController ctrl, String label, IconData icon, {bool isEmail = false, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: colorExt.primary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
        maxLines: maxLines,
        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: colorExt.primaryText),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.outfit(color: colorExt.secondaryText, fontWeight: FontWeight.w500),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: colorExt.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: colorExt.primary, size: 20),
            ),
          ),
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: colorExt.primary, width: 1.5)),
        ),
      ),
    );
  }

  Widget _regPasswordField(TextEditingController ctrl, String label, {required bool isObscured, required VoidCallback toggle}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: colorExt.primary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: TextField(
        controller: ctrl,
        obscureText: isObscured,
        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: colorExt.primaryText),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.outfit(color: colorExt.secondaryText, fontWeight: FontWeight.w500),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: colorExt.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.lock_rounded, color: colorExt.primary, size: 20),
            ),
          ),
          suffixIcon: IconButton(
            icon: Icon(isObscured ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: colorExt.secondaryText, size: 20),
            onPressed: toggle,
          ),
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: colorExt.primary, width: 1.5)),
        ),
      ),
    );
  }

  Widget _regDropdownField(String label, String? value, List<String> items, IconData icon, Function(String?) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: colorExt.primary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)))).toList(),
        onChanged: onChanged,
        style: GoogleFonts.outfit(color: colorExt.primaryText, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.outfit(color: colorExt.secondaryText, fontWeight: FontWeight.w500),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: colorExt.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: colorExt.primary, size: 20),
            ),
          ),
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: colorExt.primary, width: 1.5)),
        ),
        icon: Icon(Icons.expand_more_rounded, color: colorExt.primary),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _regActionButton(String text, VoidCallback onPressed) {
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
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(text, style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 1.1)),
      ),
    );
  }

  PinTheme _pinputTheme() {
    return PinTheme(
      width: 50,
      height: 60,
      textStyle: GoogleFonts.outfit(fontSize: 22, color: colorExt.primary, fontWeight: FontWeight.w800),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorExt.primary.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: colorExt.primary.withValues(alpha: 0.05), blurRadius: 10)],
      ),
    );
  }
}

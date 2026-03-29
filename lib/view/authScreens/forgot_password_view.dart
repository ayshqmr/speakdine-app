import 'package:firebase_auth/firebase_auth.dart';
import 'package:speak_dine/services/login_identifier_service.dart';
import 'package:speak_dine/utils/password_strength.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/widgets/auth_labeled_text_field.dart';
import 'package:speak_dine/widgets/password_strength_indicator.dart';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/widgets/keyboard_friendly.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _actionCodeController = TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _linkSent = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _actionCodeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<String?> _resolveEmail(String emailOrUsername) async {
    final value = emailOrUsername.trim();
    if (value.isEmpty) return null;
    if (value.contains('@')) return value;
    return LoginIdentifierService.resolveToEmail(value);
  }

  Future<void> _sendResetLink() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      _showMessage('Please enter email or username');
      return;
    }

    final email = await _resolveEmail(identifier);
    if (email == null || email.isEmpty) {
      _showMessage('Account not found. Please check your username/email.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _linkSent = true);
      _showMessage('Reset link sent. Paste the action code below.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Failed to send reset link.');
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyAndResetPassword() async {
    final actionCode = _actionCodeController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (actionCode.isEmpty) {
      _showMessage('Please paste the action code (oobCode).');
      return;
    }
    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showMessage('Please enter and confirm your new password.');
      return;
    }
    if (newPassword != confirmPassword) {
      _showMessage('Passwords do not match.');
      return;
    }

    final strengthError = validatePasswordStrength(newPassword);
    if (strengthError != null) {
      _showMessage(strengthError);
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Ensures the code is valid before confirming reset.
      await _auth.verifyPasswordResetCode(actionCode);

      await _auth.confirmPasswordReset(
        code: actionCode,
        newPassword: newPassword,
      );

      _showMessage('Password reset successful. Please login.');
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Invalid or expired action code.');
    } catch (_) {
      _showMessage('Failed to reset password. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Text(
                        _linkSent ? 'Reset Password' : 'Forgot Password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
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
                          Text(
                            _linkSent
                                ? 'Enter the action code and create a new password.'
                                : 'Enter your email or username to receive a reset link.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),

                          if (!_linkSent) ...[
                            AuthLabeledTextField(
                              label: 'Email',
                              controller: _identifierController,
                              placeholder: 'you@example.com',
                            ),
                            const SizedBox(height: 8),
                            PrimaryButton(
                              onPressed: _isLoading ? null : _sendResetLink,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.email_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('Send reset link'),
                                ],
                              ),
                            ),
                          ] else ...[
                            AuthLabeledTextField(
                              label: 'Action Code (oobCode)',
                              controller: _actionCodeController,
                              placeholder: 'Paste the code from the reset email',
                            ),
                            const SizedBox(height: 16),
                            AuthLabeledTextField(
                              label: 'New Password',
                              controller: _newPasswordController,
                              placeholder: 'At least 8 characters',
                              obscure: true,
                            ),
                            PasswordStrengthIndicator(
                              controller: _newPasswordController,
                            ),
                            AuthLabeledTextField(
                              label: 'Confirm Password',
                              controller: _confirmPasswordController,
                              placeholder: 'Re-enter password',
                              obscure: true,
                            ),
                            const SizedBox(height: 8),
                            PrimaryButton(
                              onPressed: _isLoading
                                  ? null
                                  : _verifyAndResetPassword,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.vpn_key_rounded, size: 16),
                                  SizedBox(width: 8),
                                  Text('Reset Password'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    OutlineButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text('Back'),
                    ),
                  ],
            ),
          ),
        ],
      ),
    );
  }
}


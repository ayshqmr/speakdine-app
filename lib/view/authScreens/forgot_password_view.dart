import 'package:firebase_auth/firebase_auth.dart';
import 'package:speak_dine/services/login_identifier_service.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/widgets/auth_labeled_text_field.dart';

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

  bool _isLoading = false;
  bool _linkSent = false;
  /// Email Firebase sent the reset link to (for display + resend).
  String? _sentToEmail;

  @override
  void dispose() {
    _identifierController.dispose();
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
      setState(() {
        _linkSent = true;
        _sentToEmail = email;
      });
      _showMessage('Reset link sent. Check your email.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Failed to send reset link.');
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendResetLink() async {
    final email = _sentToEmail ??
        await _resolveEmail(_identifierController.text.trim());
    if (email == null || email.isEmpty) {
      _showMessage('Enter your email or username again to resend.');
      setState(() => _linkSent = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _showMessage('Reset link sent again.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Failed to send reset link.');
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToLogin() {
    Navigator.pop(context);
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
                    _linkSent ? 'Check your email' : 'Forgot Password',
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
                      if (!_linkSent) ...[
                        Text(
                          'Enter your email or username to receive a reset link.',
                          style: TextStyle(
                            color: theme.colorScheme.mutedForeground,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
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
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'We sent a password reset link.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.foreground,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_sentToEmail != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _sentToEmail!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.mutedForeground,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Open the link in that email and follow the steps to choose a new password. '
                          'When you are done, your password is updated—sign in on the login screen with your new password.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.mutedForeground,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          onPressed: _isLoading ? null : _goToLogin,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login_rounded, size: 16),
                              SizedBox(width: 8),
                              Text('Go to login'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlineButton(
                          onPressed: _isLoading ? null : _resendResetLink,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.refresh_rounded, size: 16),
                              SizedBox(width: 8),
                              Text('Resend link'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() {
                                    _linkSent = false;
                                    _sentToEmail = null;
                                  }),
                          child: Text(
                            'Use a different email',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.primary,
                            ),
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

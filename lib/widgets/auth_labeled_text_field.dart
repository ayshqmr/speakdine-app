import 'package:flutter/material.dart';

class AuthLabeledTextField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final bool obscure;
  final TextInputType? keyboardType;

  const AuthLabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.placeholder,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  State<AuthLabeledTextField> createState() => _AuthLabeledTextFieldState();
}

class _AuthLabeledTextFieldState extends State<AuthLabeledTextField> {
  /// When [obscure] is true: whether the password characters are hidden.
  bool _obscured = true;

  @override
  void didUpdateWidget(covariant AuthLabeledTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.obscure && oldWidget.obscure) {
      _obscured = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPassword = widget.obscure;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: widget.controller,
            obscureText: isPassword && _obscured,
            keyboardType: widget.keyboardType,
            decoration: InputDecoration(
              hintText: widget.placeholder,
              isDense: true,
              suffixIcon: isPassword
                  ? IconButton(
                      onPressed: () =>
                          setState(() => _obscured = !_obscured),
                      tooltip: _obscured ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final TextEditingController controller;

  const PasswordStrengthIndicator({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final password = value.text;
        if (password.isEmpty) return const SizedBox.shrink();

        final checks = [
          ("8+ chars", password.length >= 8),
          ("Uppercase (A-Z)", password.contains(RegExp(r'[A-Z]'))),
          ("Lowercase (a-z)", password.contains(RegExp(r'[a-z]'))),
          ("Number (0-9)", password.contains(RegExp(r'[0-9]'))),
          (
            "Symbol (!@#\$...)",
            password.contains(
              RegExp(
                r'[!@#\$&*~%^()_\-+=\[\]{};:,.<>?/\\|`]',
              ),
            )
          ),
        ];

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            children: checks.map((c) {
              final passed = c.$2;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    passed
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 14,
                    color: passed ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    c.$1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: passed ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }
}


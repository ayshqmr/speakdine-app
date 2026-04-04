/// Password strength rules shared across the app.
///
/// Based on SD-lib's password strength criteria:
/// - At least 8 characters
/// - 1 uppercase letter (A-Z)
/// - 1 lowercase letter (a-z)
/// - 1 number (0-9)
/// - 1 special character (symbols)
int calcPasswordStrength(String password) {
  int score = 0;
  if (password.length >= 8) {
    score++;
  }
  if (password.contains(RegExp(r'[A-Z]'))) {
    score++;
  }
  if (password.contains(RegExp(r'[a-z]'))) {
    score++;
  }
  if (password.contains(RegExp(r'[0-9]'))) {
    score++;
  }
  if (password.contains(
    RegExp(r'[!@#\$&*~%^()_\-+=\[\]{};:,.<>?/\\|`]'),
  )) {
    score++;
  }
  return score;
}

String? validatePasswordStrength(String? password) {
  if (password == null || password.isEmpty) {
    return "Password is required";
  }
  if (password.length < 8) return "At least 8 characters";
  if (!password.contains(RegExp(r'[A-Z]'))) {
    return "Add at least 1 uppercase letter (A-Z)";
  }
  if (!password.contains(RegExp(r'[a-z]'))) {
    return "Add at least 1 lowercase letter (a-z)";
  }
  if (!password.contains(RegExp(r'[0-9]'))) {
    return "Add at least 1 number (0-9)";
  }
  if (!password.contains(
    RegExp(r'[!@#\$&*~%^()_\-+=\[\]{};:,.<>?/\\|`]'),
  )) {
    return "Add at least 1 special character (!@#\$...)";
  }
  return null;
}


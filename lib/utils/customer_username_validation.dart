// Rules for customer users.name, used as the username for email/password sign-in.
// Allowed: a–z, 0–9, and a set of ASCII symbols. No spaces or uppercase.

const _symbolChars = {
  '!',
  '@',
  '#',
  r'$',
  '%',
  '^',
  '&',
  '*',
  '(',
  ')',
  '_',
  '+',
  '-',
  '=',
  '[',
  ']',
  '{',
  '}',
  '|',
  ';',
  ':',
  "'",
  '"',
  ',',
  '.',
  '/',
  '<',
  '>',
  '?',
  '`',
  '~',
};

bool _charAllowedInCustomerUsername(String c) {
  if (c.length != 1) return false;
  if (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) return true;
  if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) return true;
  return _symbolChars.contains(c);
}

/// Maps spoken names (e.g. from voice) into stored usernames: lowercase, spaces to underscores,
/// drops characters that are not allowed in [validateCustomerUsernameFormat].
String normalizeCustomerUsernameFromSpeech(String raw) {
  final lower = raw.trim().toLowerCase();
  if (lower.isEmpty) return '';
  final withUnderscores = lower.replaceAll(RegExp(r'\s+'), '_');
  final buf = StringBuffer();
  for (var i = 0; i < withUnderscores.length; i++) {
    final c = withUnderscores[i];
    if (_charAllowedInCustomerUsername(c)) buf.write(c);
  }
  return buf.toString();
}

/// Returns `null` if [raw] is valid (after trim), otherwise a short error message.
String? validateCustomerUsernameFormat(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    return null;
  }
  for (var i = 0; i < s.length; i++) {
    if (!_charAllowedInCustomerUsername(s[i])) {
      return 'Username may only use lowercase letters, numbers, and symbols '
          '(no spaces or capital letters).';
    }
  }
  return null;
}

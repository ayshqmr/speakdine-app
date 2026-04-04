import 'package:speak_dine/services/cart_service.dart';

/// Parses short natural-language phrases and updates [cartService] lines by fuzzy name match.
class CartNaturalLanguage {
  CartNaturalLanguage._();

  /// Returns a single phrase suitable for TTS after applying all understood clauses.
  static String applyFromUtterance(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Say what to change, for example remove pizza or add one more coffee.';
    }
    if (cartService.isEmpty) {
      return 'Your cart is empty. Add items from a restaurant menu first.';
    }

    final clauses = _splitClauses(trimmed);
    var ok = 0;
    var failed = 0;

    for (final c in clauses) {
      final t = c.trim();
      if (t.isEmpty) {
        continue;
      }
      final r = _applyClause(t);
      if (r == _Apply.ok) {
        ok++;
      } else if (r == _Apply.fail) {
        failed++;
      }
    }

    if (ok > 0 && failed == 0) {
      return 'I have updated your cart. Would you like anything else?';
    }
    if (ok > 0 && failed > 0) {
      return 'I updated part of your cart. Some parts did not match a line in your cart. '
          'Would you like anything else?';
    }
    return 'I could not match that to items in your cart. Try naming something already in your cart, '
        'or open the cart to check names.';
  }

  static List<String> _splitClauses(String s) {
    return s
        .split(RegExp(r'\s+and\s+|\s*,\s*|\s*;\s*', caseSensitive: false))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static _Apply _applyClause(String clause) {
    final lower = clause.toLowerCase().trim();

    const removePrefixes = [
      'remove ',
      'delete ',
      'take out ',
      'get rid of ',
      'drop ',
    ];
    for (final p in removePrefixes) {
      if (lower.startsWith(p)) {
        final name = clause.substring(p.length).trim();
        return _removeLine(name) ? _Apply.ok : _Apply.fail;
      }
    }

    const decreaseHints = [
      'one less ',
      'decrease ',
      'reduce ',
      'remove one ',
      'minus one ',
    ];
    for (final p in decreaseHints) {
      if (lower.startsWith(p)) {
        final name = clause.substring(p.length).trim();
        return _decreaseLine(name) ? _Apply.ok : _Apply.fail;
      }
    }

    const addMorePrefixes = [
      'add one more ',
      'add another ',
      'one more ',
      'another ',
      'add more ',
      'extra ',
    ];
    for (final p in addMorePrefixes) {
      if (lower.startsWith(p)) {
        final name = clause.substring(p.length).trim();
        return _increaseLine(name) ? _Apply.ok : _Apply.fail;
      }
    }

    if (lower.startsWith('add ') && !lower.contains(' to cart')) {
      final name = clause.substring(4).trim();
      if (name.isNotEmpty && _increaseLine(name)) {
        return _Apply.ok;
      }
    }

    return _Apply.noop;
  }

  static bool _nameMatches(String cartName, String needle) {
    final n = cartName.toLowerCase();
    final q = needle.toLowerCase().trim();
    if (q.isEmpty) {
      return false;
    }
    if (n == q || n.contains(q) || q.contains(n)) {
      return true;
    }
    for (final w in q.split(RegExp(r'\s+')).where((e) => e.length > 2)) {
      if (n.contains(w)) {
        return true;
      }
    }
    return false;
  }

  static bool _removeLine(String needle) {
    for (final e in cartService.cart.entries) {
      final rid = e.key;
      final items = e.value;
      for (var i = items.length - 1; i >= 0; i--) {
        final name = (items[i]['name'] ?? '').toString();
        if (_nameMatches(name, needle)) {
          cartService.removeItem(rid, i);
          return true;
        }
      }
    }
    return false;
  }

  static bool _increaseLine(String needle) {
    for (final e in cartService.cart.entries) {
      final rid = e.key;
      final items = e.value;
      for (var i = 0; i < items.length; i++) {
        final name = (items[i]['name'] ?? '').toString();
        if (_nameMatches(name, needle)) {
          cartService.increaseQuantity(rid, i);
          return true;
        }
      }
    }
    return false;
  }

  static bool _decreaseLine(String needle) {
    for (final e in cartService.cart.entries) {
      final rid = e.key;
      final items = e.value;
      for (var i = 0; i < items.length; i++) {
        final name = (items[i]['name'] ?? '').toString();
        if (_nameMatches(name, needle)) {
          cartService.decreaseQuantity(rid, i);
          return true;
        }
      }
    }
    return false;
  }
}

enum _Apply { ok, fail, noop }

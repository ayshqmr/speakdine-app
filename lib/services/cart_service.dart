// Global cart service to manage cart state across the app

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';

class CartService {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  static const _prefsKey = 'speakdine_cart_v1';

  /// Loaded from disk for this Firebase user (customer). Cleared on mismatch.
  final Map<String, List<Map<String, dynamic>>> cart = {};

  int get totalItems {
    int count = 0;
    cart.forEach((key, items) {
      for (var item in items) {
        count += (item['quantity'] as int? ?? 1);
      }
    });
    return count;
  }

  double get totalAmount {
    double total = 0;
    cart.forEach((restaurantId, items) {
      for (var item in items) {
        final p = item['price'];
        final price = p is num ? p.toDouble() : double.tryParse('$p') ?? 0;
        total += price * (item['quantity'] ?? 1);
      }
    });
    return total;
  }

  void _notifyCartUi() {
    CustomerVoiceBridge.instance.notifyCartChanged?.call();
  }

  /// Clears memory + local prefs (call before customer [FirebaseAuth.signOut]).
  Future<void> clearSessionForSignOut() async {
    cart.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e, st) {
      debugPrint('[CartService] clearSessionForSignOut: $e\n$st');
    }
    _notifyCartUi();
  }

  /// Call when opening the customer shell for [uid] (logged-in customer).
  Future<void> restoreForCustomer(String uid) async {
    cart.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        _notifyCartUi();
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>?;
      if (decoded == null) {
        _notifyCartUi();
        return;
      }
      final savedUid = decoded['uid'] as String?;
      if (savedUid != uid) {
        await prefs.remove(_prefsKey);
        _notifyCartUi();
        return;
      }
      final dataRaw = decoded['cart'];
      if (dataRaw is! Map) {
        _notifyCartUi();
        return;
      }
      final data = Map<String, dynamic>.from(dataRaw);
      data.forEach((key, value) {
        if (value is! List) return;
        cart[key] = value.map((e) {
          if (e is Map<String, dynamic>) {
            return _normalizeItem(e);
          }
          if (e is Map) {
            return _normalizeItem(Map<String, dynamic>.from(e));
          }
          return <String, dynamic>{};
        }).where((m) => m.isNotEmpty).toList();
      });
      cart.removeWhere((_, items) => items.isEmpty);
    } catch (e, st) {
      debugPrint('[CartService] restore failed: $e\n$st');
    }
    _notifyCartUi();
  }

  Map<String, dynamic> _normalizeItem(Map<String, dynamic> m) {
    final q = m['quantity'];
    final p = m['price'];
    final quantity = q is int
        ? q
        : q is num
            ? q.toInt()
            : int.tryParse('$q') ?? 1;
    final price = p is num ? p.toDouble() : double.tryParse('$p') ?? 0.0;
    return {
      'itemId': '${m['itemId'] ?? ''}',
      'name': '${m['name'] ?? ''}',
      'price': price,
      'description': m['description']?.toString() ?? '',
      'note': m['note']?.toString() ?? '',
      'quantity': quantity.clamp(1, 999),
      'restaurantId': '${m['restaurantId'] ?? ''}',
      'restaurantName': '${m['restaurantName'] ?? ''}',
    };
  }

  Future<void> _persist() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
      } catch (e, st) {
        debugPrint('[CartService] persist (signed out) failed: $e\n$st');
      }
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cart.isEmpty) {
        await prefs.remove(_prefsKey);
        return;
      }
      final serializable = <String, dynamic>{};
      cart.forEach((rid, items) {
        serializable[rid] = items.map((e) => Map<String, dynamic>.from(e)).toList();
      });
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'uid': uid,
          'cart': serializable,
        }),
      );
    } catch (e, st) {
      debugPrint('[CartService] persist failed: $e\n$st');
    }
  }

  void addItem(
    String restaurantId,
    String restaurantName,
    Map<String, dynamic> item,
    String itemId,
  ) {
    if (!cart.containsKey(restaurantId)) {
      cart[restaurantId] = [];
    }

    final existingIndex = cart[restaurantId]!
        .indexWhere((cartItem) => cartItem['itemId'] == itemId);

    if (existingIndex >= 0) {
      cart[restaurantId]![existingIndex]['quantity']++;
    } else {
      final p = item['price'];
      final price = p is num ? p.toDouble() : double.tryParse('$p') ?? 0.0;
      cart[restaurantId]!.add({
        'itemId': itemId,
        'name': item['name'],
        'price': price,
        'description': item['description'],
        'note': item['note']?.toString() ?? '',
        'quantity': 1,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
      });
    }
    _persist();
    _notifyCartUi();
  }

  void increaseQuantity(String restaurantId, int index) {
    cart[restaurantId]![index]['quantity']++;
    _persist();
    _notifyCartUi();
  }

  void decreaseQuantity(String restaurantId, int index) {
    if (cart[restaurantId]![index]['quantity'] > 1) {
      cart[restaurantId]![index]['quantity']--;
    } else {
      cart[restaurantId]!.removeAt(index);
      if (cart[restaurantId]!.isEmpty) {
        cart.remove(restaurantId);
      }
    }
    _persist();
    _notifyCartUi();
  }

  void removeItem(String restaurantId, int index) {
    cart[restaurantId]!.removeAt(index);
    if (cart[restaurantId]!.isEmpty) {
      cart.remove(restaurantId);
    }
    _persist();
    _notifyCartUi();
  }

  void updateItemNote(String restaurantId, int index, String note) {
    final list = cart[restaurantId];
    if (list == null || index < 0 || index >= list.length) {
      return;
    }
    list[index]['note'] = note.trim();
    _persist();
    _notifyCartUi();
  }

  void clearCart() {
    cart.clear();
    _persist();
    _notifyCartUi();
  }

  int getItemQuantity(String restaurantId, String itemId) {
    if (!cart.containsKey(restaurantId)) return 0;
    final cartItem = cart[restaurantId]!
        .where((ci) => ci['itemId'] == itemId)
        .toList();
    if (cartItem.isNotEmpty) {
      return cartItem.first['quantity'] ?? 0;
    }
    return 0;
  }

  bool get isEmpty => cart.isEmpty;

  bool get isNotEmpty => cart.isNotEmpty;

  bool _nameMatches(String cartName, String needle) {
    final n = cartName.toLowerCase().trim();
    final q = needle.toLowerCase().trim();
    if (n.isEmpty || q.isEmpty) {
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

  int setNoteForMatchingItems(String itemNeedle, String note) {
    final trimmedNeedle = itemNeedle.trim();
    if (trimmedNeedle.isEmpty) {
      return 0;
    }
    var updates = 0;
    for (final entry in cart.entries) {
      for (final item in entry.value) {
        final name = (item['name'] ?? '').toString();
        if (_nameMatches(name, trimmedNeedle)) {
          item['note'] = note.trim();
          updates++;
        }
      }
    }
    if (updates > 0) {
      _persist();
      _notifyCartUi();
    }
    return updates;
  }

  int clearNoteForMatchingItems(String itemNeedle) {
    return setNoteForMatchingItems(itemNeedle, '');
  }

  bool hasMatchingItem(String itemNeedle) {
    final trimmedNeedle = itemNeedle.trim();
    if (trimmedNeedle.isEmpty) {
      return false;
    }
    for (final entry in cart.entries) {
      for (final item in entry.value) {
        final name = (item['name'] ?? '').toString();
        if (_nameMatches(name, trimmedNeedle)) {
          return true;
        }
      }
    }
    return false;
  }

  String? firstNoteForMatchingItem(String itemNeedle) {
    final trimmedNeedle = itemNeedle.trim();
    if (trimmedNeedle.isEmpty) {
      return null;
    }
    for (final entry in cart.entries) {
      for (final item in entry.value) {
        final name = (item['name'] ?? '').toString();
        if (!_nameMatches(name, trimmedNeedle)) {
          continue;
        }
        final note = (item['note'] ?? '').toString().trim();
        if (note.isNotEmpty) {
          return note;
        }
      }
    }
    return null;
  }

  List<String> cartItemNames({bool unique = true}) {
    final names = <String>[];
    final seen = <String>{};
    for (final entry in cart.entries) {
      for (final item in entry.value) {
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          continue;
        }
        final key = name.toLowerCase();
        if (unique && seen.contains(key)) {
          continue;
        }
        seen.add(key);
        names.add(name);
      }
    }
    return names;
  }

  String? firstMatchingItemNameInText(String text) {
    final lower = text.toLowerCase();
    for (final entry in cart.entries) {
      for (final item in entry.value) {
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          continue;
        }
        if (lower.contains(name.toLowerCase())) {
          return name;
        }
      }
    }
    return null;
  }
}

final cartService = CartService();

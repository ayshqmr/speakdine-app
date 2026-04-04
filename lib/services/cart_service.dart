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
}

final cartService = CartService();

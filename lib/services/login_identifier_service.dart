import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:speak_dine/config/api_keys.dart';

/// Resolves username / restaurant name to email: [loginLookup] first, then optional server.
class LoginIdentifierService {
  LoginIdentifierService._();

  static String get _baseUrl {
    final u = stripeServerUrl.trim();
    if (u.isEmpty) return '';
    return u.endsWith('/') ? u.substring(0, u.length - 1) : u;
  }

  static Future<String?> _fromLoginLookup(String normalizedKey) async {
    if (normalizedKey.isEmpty) return null;
    final fs = FirebaseFirestore.instance;
    for (final docId in <String>['u_$normalizedKey', 'r_$normalizedKey']) {
      try {
        final snap = await fs.collection('loginLookup').doc(docId).get();
        if (snap.exists) {
          final e = snap.data()?['email'] as String?;
          final out = e?.trim();
          if (out != null && out.isNotEmpty && out.contains('@')) {
            return out;
          }
        }
      } catch (e, st) {
        debugPrint('[LoginIdentifier] loginLookup $docId: $e\n$st');
      }
    }
    return null;
  }

  static Future<String?> _fromServer(String trimmed) async {
    final base = _baseUrl;
    final secret = loginResolveSecret.trim();
    if (base.isEmpty || secret.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse('$base/resolve-login-identifier'),
        headers: {
          'Content-Type': 'application/json',
          'X-Login-Resolve-Secret': secret,
        },
        body: jsonEncode({'identifier': trimmed}),
      );

      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        final email = map['email'] as String?;
        final out = email?.trim();
        if (out != null && out.isNotEmpty) return out;
        return null;
      }

      debugPrint('[LoginIdentifier] server ${response.statusCode} ${response.body}');
      return null;
    } catch (e, st) {
      debugPrint('[LoginIdentifier] server $e\n$st');
      return null;
    }
  }

  /// Returns email for sign-in / password reset. For values containing `@`, returns trimmed input.
  static Future<String?> resolveToEmail(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('@')) return trimmed;

    final key = trimmed.toLowerCase();
    final local = await _fromLoginLookup(key);
    if (local != null) return local;

    return _fromServer(trimmed);
  }

  static bool get isConfigured =>
      stripeServerUrl.trim().isNotEmpty &&
      loginResolveSecret.trim().isNotEmpty;
}

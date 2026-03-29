import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:speak_dine/config/api_keys.dart';
import 'package:speak_dine/services/login_lookup_sync.dart';

enum AuthRouteType { customer, restaurant }

class GoogleAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static bool _didInit = false;

  Future<void> _ensureGoogleInit() async {
    if (_didInit) return;
    final webId = googleWebClientId.trim();
    await GoogleSignIn.instance.initialize(
      serverClientId: webId.isEmpty ? null : webId,
    );
    _didInit = true;
  }

  /// Signs in with Google, then ensures a Firestore profile exists so routing works.
  ///
  /// If no profile exists for the signed-in UID, a `customer` profile is created by default.
  Future<AuthRouteType?> signInWithGoogleAndUpsert({
    bool defaultCustomer = true,
  }) async {
    await _ensureGoogleInit();

    try {
      final account = await GoogleSignIn.instance.authenticate();

      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) return null;

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      final uid = user.uid;
      final name = user.displayName ?? 'User';
      final email = user.email ?? '';

      return _ensureProfile(
        uid: uid,
        name: name,
        email: email,
        defaultCustomer: defaultCustomer,
      );
    } on GoogleSignInException catch (e, st) {
      debugPrint('GoogleSignInException: ${e.code} ${e.description}');
      debugPrint('$st');
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<AuthRouteType> _ensureProfile({
    required String uid,
    required String name,
    required String email,
    required bool defaultCustomer,
  }) async {
    // If restaurant doc exists, route as restaurant.
    final restaurantDoc =
        await _firestore.collection('restaurants').doc(uid).get();
    if (restaurantDoc.exists) {
      // Best-effort: fill missing email/name fields.
      final data = restaurantDoc.data();
      final maybeEmail = (data?['email'] as String?)?.trim();
      if ((maybeEmail == null || maybeEmail.isEmpty) && email.isNotEmpty) {
        await restaurantDoc.reference.update({'email': email});
      }
      return AuthRouteType.restaurant;
    }

    // If user doc exists, route as customer.
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final data = userDoc.data();
      final maybeEmail = (data?['email'] as String?)?.trim();
      final maybeName = (data?['name'] as String?)?.trim();
      final updates = <String, dynamic>{};
      if ((maybeEmail == null || maybeEmail.isEmpty) && email.isNotEmpty) {
        updates['email'] = email;
      }
      if ((maybeName == null || maybeName.isEmpty) && name.isNotEmpty) {
        updates['name'] = name;
      }
      if (updates.isNotEmpty) {
        await userDoc.reference.update(updates);
      }
      return AuthRouteType.customer;
    }

    // No doc exists: create default profile.
    if (!defaultCustomer) {
      // For now we default to customer because your current app routing
      // expects either `users/{uid}` or `restaurants/{uid}`. If you want to
      // create restaurants by default, tell me and we can switch this logic.
      throw StateError('defaultCustomer=false but no restaurant profile creation is implemented.');
    }

    var displayName = name.trim();
    if (displayName.isEmpty) {
      displayName = 'user_${uid.substring(0, 8)}';
    }
    Future<LoginLookupSyncResult> claim(String n) =>
        LoginLookupSync.syncCustomerDisplayName(
          firestore: _firestore,
          uid: uid,
          email: email,
          previousName: null,
          newName: n,
        );
    var res = await claim(displayName);
    if (res == LoginLookupSyncResult.nameAlreadyClaimed) {
      displayName = '${displayName}_${uid.substring(0, 8)}';
      res = await claim(displayName);
    }
    if (res == LoginLookupSyncResult.nameAlreadyClaimed) {
      displayName = 'id_${uid.replaceAll('-', '')}';
      res = await claim(displayName);
    }
    if (res != LoginLookupSyncResult.success) {
      debugPrint(
        '[GoogleAuthService] loginLookup claim failed for uid $uid; '
        'profile created without username sign-in.',
      );
    }
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'name': displayName,
      'email': email,
      'phone': '',
      'city': '',
      'role': 'customer',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return AuthRouteType.customer;
  }
}


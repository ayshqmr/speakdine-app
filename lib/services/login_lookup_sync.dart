import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Outcome of syncing a display / restaurant name into [loginLookup].
enum LoginLookupSyncResult {
  /// Lookup updated (or no change needed).
  success,

  /// Another account already owns this name with an active profile.
  nameAlreadyClaimed,

  /// Firestore error, permission, or aborted transaction — not a name conflict.
  failed,
}

/// Public [loginLookup] docs allow username → email sign-in without a backend.
///
/// Doc ids: `u_{lowercaseName}` for customers, `r_{lowercaseRestaurantName}` for restaurants.
/// Each doc is owned by one [uid]; [syncCustomerDisplayName] / [syncRestaurantName] use a
/// transaction so two accounts cannot claim the same sign-in name.
///
/// [syncCustomerDisplayName] cannot read other users' [/users] docs (Firestore rules), so if
/// [loginLookup] already maps a name to another [uid], we report [LoginLookupSyncResult.nameAlreadyClaimed]
/// without stale-row cleanup on the client. Pruning orphaned lookup rows is a backend/admin concern.
class LoginLookupSync {
  LoginLookupSync._();

  static String _customerDocId(String displayName) =>
      'u_${displayName.trim().toLowerCase()}';

  static String _restaurantDocId(String restaurantName) =>
      'r_${restaurantName.trim().toLowerCase()}';

  /// True when [loginLookup] maps this restaurant name to a **different** account that still
  /// has a [restaurants] document (real collision). Stale rows (no restaurant doc) are ignored.
  static Future<bool> isRestaurantNameInUseByAnotherVenue(
    FirebaseFirestore firestore,
    String restaurantName,
    String registeringUid,
  ) async {
    final snap = await firestore
        .collection('loginLookup')
        .doc(_restaurantDocId(restaurantName))
        .get();
    if (!snap.exists) return false;
    final owner = snap.data()?['uid'] as String?;
    if (owner == null || owner == registeringUid) return false;
    final rest = await firestore.collection('restaurants').doc(owner).get();
    return rest.exists;
  }

  /// True when [loginLookup] maps this customer name to another account that still has a [users] doc.
  static Future<bool> isCustomerUsernameInUseByAnotherAccount(
    FirebaseFirestore firestore,
    String displayName,
    String registeringUid,
  ) async {
    final snap = await firestore
        .collection('loginLookup')
        .doc(_customerDocId(displayName))
        .get();
    if (!snap.exists) return false;
    final owner = snap.data()?['uid'] as String?;
    if (owner == null || owner == registeringUid) return false;
    final u = await firestore.collection('users').doc(owner).get();
    return u.exists;
  }

  static Future<LoginLookupSyncResult> syncCustomerDisplayName({
    required FirebaseFirestore firestore,
    required String uid,
    required String email,
    required String? previousName,
    required String newName,
  }) async {
    final prev = previousName?.trim() ?? '';
    final neu = newName.trim();
    final e = email.trim();
    if (e.isEmpty || !e.contains('@')) return LoginLookupSyncResult.success;

    var conflict = false;
    try {
      await firestore.runTransaction((txn) async {
        conflict = false;

        final oldKey =
            prev.isNotEmpty ? _customerDocId(prev) : null;
        final newKey =
            neu.isNotEmpty ? _customerDocId(neu) : null;

        if (neu.isEmpty) {
          if (oldKey != null) {
            final oldRef = firestore.collection('loginLookup').doc(oldKey);
            final oldSnap = await txn.get(oldRef);
            if (oldSnap.exists && oldSnap.data()?['uid'] == uid) {
              txn.delete(oldRef);
            }
          }
          return;
        }

        final newRef = firestore.collection('loginLookup').doc(newKey!);
        final newSnap = await txn.get(newRef);
        if (newSnap.exists) {
          final existingUid = newSnap.data()?['uid'] as String?;
          if (existingUid != null && existingUid != uid) {
            conflict = true;
            return;
          }
        }

        if (prev.isNotEmpty &&
            oldKey != null &&
            oldKey != newKey) {
          final oldRef = firestore.collection('loginLookup').doc(oldKey);
          final oldSnap = await txn.get(oldRef);
          if (oldSnap.exists && oldSnap.data()?['uid'] == uid) {
            txn.delete(oldRef);
          }
        }

        txn.set(newRef, {'uid': uid, 'email': e}, SetOptions(merge: true));
      });
    } catch (err, st) {
      if (err is FirebaseException) {
        debugPrint(
          '[LoginLookupSync] syncCustomerDisplayName '
          'code=${err.code} message=${err.message}',
        );
      } else {
        debugPrint('[LoginLookupSync] syncCustomerDisplayName $err\n$st');
      }
      return LoginLookupSyncResult.failed;
    }
    if (conflict) return LoginLookupSyncResult.nameAlreadyClaimed;
    return LoginLookupSyncResult.success;
  }

  static Future<LoginLookupSyncResult> syncRestaurantName({
    required FirebaseFirestore firestore,
    required String uid,
    required String email,
    required String? previousName,
    required String newName,
  }) async {
    final prev = previousName?.trim() ?? '';
    final neu = newName.trim();
    final e = email.trim();
    if (e.isEmpty || !e.contains('@')) return LoginLookupSyncResult.success;

    var conflict = false;
    try {
      await firestore.runTransaction((txn) async {
        conflict = false;

        final oldKey =
            prev.isNotEmpty ? _restaurantDocId(prev) : null;
        final newKey =
            neu.isNotEmpty ? _restaurantDocId(neu) : null;

        if (neu.isEmpty) {
          if (oldKey != null) {
            final oldRef = firestore.collection('loginLookup').doc(oldKey);
            final oldSnap = await txn.get(oldRef);
            if (oldSnap.exists && oldSnap.data()?['uid'] == uid) {
              txn.delete(oldRef);
            }
          }
          return;
        }

        final newRef = firestore.collection('loginLookup').doc(newKey!);
        final newSnap = await txn.get(newRef);
        if (newSnap.exists) {
          final existingUid = newSnap.data()?['uid'] as String?;
          if (existingUid != null && existingUid != uid) {
            final profileRef =
                firestore.collection('restaurants').doc(existingUid);
            final profileSnap = await txn.get(profileRef);
            if (profileSnap.exists) {
              conflict = true;
              return;
            }
            txn.delete(newRef);
          }
        }

        if (prev.isNotEmpty &&
            oldKey != null &&
            oldKey != newKey) {
          final oldRef = firestore.collection('loginLookup').doc(oldKey);
          final oldSnap = await txn.get(oldRef);
          if (oldSnap.exists && oldSnap.data()?['uid'] == uid) {
            txn.delete(oldRef);
          }
        }

        txn.set(newRef, {'uid': uid, 'email': e}, SetOptions(merge: true));
      });
    } catch (err, st) {
      debugPrint('[LoginLookupSync] syncRestaurantName $err\n$st');
      return LoginLookupSyncResult.failed;
    }
    if (conflict) return LoginLookupSyncResult.nameAlreadyClaimed;
    return LoginLookupSyncResult.success;
  }
}

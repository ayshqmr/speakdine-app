import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
class NotificationService {
  static CollectionReference<Map<String, dynamic>> _itemsRef(String userId) =>
      FirebaseFirestore.instance
          .collection('notifications')
          .doc(userId)
          .collection('items');

  /// Creates a notification document with title, message, optional orderId,
  /// read (false), and createdAt (server timestamp).
  static Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
    String? orderId,
  }) async {
    try {
      await _itemsRef(userId).add({
        'title': title,
        'message': message,
        if (orderId != null) 'orderId': orderId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint('NotificationService.createNotification: $e\n$st');
      rethrow;
    }
  }

  /// Returns a stream of notifications ordered by createdAt descending.
  static Stream<QuerySnapshot<Map<String, dynamic>>> getNotifications(
    String userId,
  ) {
    return _itemsRef(userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Sets read to true for the specified notification.
  static Future<void> markAsRead(String userId, String notificationId) async {
    try {
      await _itemsRef(userId).doc(notificationId).update({'read': true});
    } catch (e, st) {
      debugPrint('NotificationService.markAsRead: $e\n$st');
      rethrow;
    }
  }

  /// Marks all unread notifications as read.
  static Future<void> markAllAsRead(String userId) async {
    try {
      final unread = await _itemsRef(userId)
          .where('read', isEqualTo: false)
          .get();

      if (unread.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e, st) {
      debugPrint('NotificationService.markAllAsRead: $e\n$st');
      rethrow;
    }
  }

  /// Returns a stream of unread notification count.
  static Stream<int> getUnreadCount(String userId) {
    return _itemsRef(userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// One-shot unread count (no realtime listener).
  static Future<int> fetchUnreadCount(String userId) async {
    final snap =
        await _itemsRef(userId).where('read', isEqualTo: false).get();
    return snap.docs.length;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Spoken summary for order tracking (matches [OrderTrackingView] ETA logic).
String buildOrderTrackingVoiceSummary(Map<String, dynamic> order) {
  final restaurantName = (order['restaurantName'] ?? 'Restaurant')
      .toString()
      .trim();
  final status = (order['status'] as String? ?? 'pending').trim();
  final statusLine = _statusDescription(status);
  final etaLine = _etaLine(order, status);
  return '$restaurantName: $statusLine $etaLine';
}

String _statusDescription(String status) {
  switch (status) {
    case 'pending':
      return 'Your order is pending — waiting for the restaurant to accept.';
    case 'accepted':
      return 'Your order was accepted and is being processed.';
    case 'in_kitchen':
      return 'Your food is being prepared in the kitchen.';
    case 'handed_to_rider':
      return 'Your order has been handed to the rider.';
    case 'on_the_way':
      return 'Your order is on the way to you.';
    case 'delivered':
      return 'Your order has been delivered.';
    default:
      return 'Current status is $status.';
  }
}

String _etaLine(Map<String, dynamic> order, String status) {
  if (status == 'delivered') {
    return 'No time remaining — delivery is complete.';
  }
  final estimatedMinutes = order['estimatedMinutes'];
  final acceptedAt = order['acceptedAt'];
  if (estimatedMinutes is! int || acceptedAt is! Timestamp) {
    return 'Estimated time remaining is not available yet.';
  }
  final deliveryTime = acceptedAt.toDate().add(
    Duration(minutes: estimatedMinutes),
  );
  final diff = deliveryTime.difference(DateTime.now());
  if (diff.isNegative || diff == Duration.zero) {
    return 'Estimated delivery window has passed — your order should arrive any moment now.';
  }
  final minutes = diff.inMinutes;
  final seconds = diff.inSeconds % 60;
  if (minutes >= 60) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return 'About $h hour${h == 1 ? '' : 's'} and $m minutes remaining until estimated delivery.';
  }
  return 'About $minutes minutes and $seconds seconds remaining until estimated delivery.';
}

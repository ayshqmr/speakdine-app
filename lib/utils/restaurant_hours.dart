import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Shared open/closed logic for restaurant maps (home list, filters).
bool isRestaurantOpenNow(Map<String, dynamic> restaurant) {
  final openTime = restaurant['openTime'] as String?;
  final closeTime = restaurant['closeTime'] as String?;
  if (openTime == null || closeTime == null) return true;

  final now = TimeOfDay.now();
  final open = _parseAmPmTime(openTime);
  final close = _parseAmPmTime(closeTime);
  if (open == null || close == null) return true;

  final nowMinutes = now.hour * 60 + now.minute;
  final openMinutes = open.hour * 60 + open.minute;
  final closeMinutes = close.hour * 60 + close.minute;

  if (closeMinutes > openMinutes) {
    return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
  }
  return nowMinutes >= openMinutes || nowMinutes < closeMinutes;
}

TimeOfDay? _parseAmPmTime(String timeStr) {
  final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false)
      .firstMatch(timeStr);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final period = match.group(3)!.toUpperCase();
  if (period == 'AM' && hour == 12) hour = 0;
  if (period == 'PM' && hour != 12) hour += 12;
  return TimeOfDay(hour: hour, minute: minute);
}

import 'package:intl/intl.dart';

/// Pakistani Rupee UI: **Rs.** prefix + thousands separators (values stored as PKR, not paisa).
final _pkrNumber = NumberFormat('#,##0.00', 'en_US');

num _asNum(Object? value) {
  if (value == null) return 0;
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

/// e.g. `Rs. 1,250.00`
String formatPkr(Object? value) => 'Rs. ${_pkrNumber.format(_asNum(value))}';

import 'package:geocoding/geocoding.dart';

/// Lowercase, trimmed, collapsed spaces — for comparing cities across profiles.
/// Strips a trailing region/country segment so e.g. `Lahore, Punjab` matches `Lahore`.
String? normalizeCityKey(String? raw) {
  if (raw == null) return null;
  var s = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  final comma = s.indexOf(',');
  if (comma > 0) {
    s = s.substring(0, comma).trim();
  }
  if (s.isEmpty) return null;
  return s;
}

/// Discovery city from a Nominatim [address] object (English, `accept-language=en`).
String? cityFromNominatimAddress(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  String? g(String k) {
    final v = raw[k];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  return g('city') ??
      g('town') ??
      g('village') ??
      g('municipality') ??
      g('city_district') ??
      g('county');
}

/// Prefer locality; fall back to sub-admin / admin area for geocoded picks.
String? cityFromPlacemark(Placemark p) {
  final loc = p.locality?.trim();
  if (loc != null && loc.isNotEmpty) return loc;
  final sub = p.subAdministrativeArea?.trim();
  if (sub != null && sub.isNotEmpty) return sub;
  final adm = p.administrativeArea?.trim();
  if (adm != null && adm.isNotEmpty) return adm;
  return null;
}

/// True if this restaurant should appear for a customer browsing [userCityKey].
/// When the venue has no city saved yet, we still show it (owner can set city in Profile).
bool restaurantCityMatchesUserExplore(
  String? userCityKey,
  Map<String, dynamic> data,
) {
  if (userCityKey == null) return true;
  final rKey = normalizeCityKey(data['city'] as String?);
  if (rKey == null) return true;
  return rKey == userCityKey;
}

/// Concatenate fields customers might type in the search bar.
String _restaurantSearchBlob(Map<String, dynamic> data) {
  final parts = <String>[];
  for (final key in [
    'restaurantName',
    'name',
    'businessName',
    'description',
    'address',
    'city',
  ]) {
    final v = data[key];
    final s = v == null ? '' : v.toString().trim();
    if (s.isNotEmpty) parts.add(s);
  }
  return parts.join(' ').toLowerCase();
}

/// Case-insensitive match on substring and per-word prefixes (e.g. `jay` → “Jay Bees”).
bool restaurantMatchesExploreSearch(
  Map<String, dynamic> data,
  String queryRaw,
) {
  final q = queryRaw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (q.isEmpty) return true;
  final blob = _restaurantSearchBlob(data);
  if (blob.contains(q)) return true;

  final qTokens =
      q.split(' ').where((t) => t.isNotEmpty).toList();
  if (qTokens.isEmpty) return true;

  final words = blob
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();

  bool tokenMatches(String qt) {
    if (blob.contains(qt)) return true;
    return words.any((w) => w.startsWith(qt) || w.contains(qt));
  }

  return qTokens.every(tokenMatches);
}

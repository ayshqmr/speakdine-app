import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/utils/city_normalize.dart';
import 'package:speak_dine/utils/restaurant_hours.dart';

/// One page of restaurant display names for voice (home explore rules).
class RestaurantNamePage {
  const RestaurantNamePage({
    required this.names,
    required this.hasMore,
    required this.total,
  });

  final List<String> names;
  final bool hasMore;
  final int total;
}

/// Match [UserHomeView] list: city, optional category, optional open-now.
Future<RestaurantNamePage?> fetchRestaurantNamesForVoice({
  required String? categoryId,
  required int offset,
  required int limit,
  bool openNowOnly = false,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return null;
  }
  final firestore = FirebaseFirestore.instance;
  final userSnap = await firestore.collection('users').doc(user.uid).get();
  final cityKey = normalizeCityKey(userSnap.data()?['city'] as String?);
  if (cityKey == null) {
    return null;
  }
  final docs = await firestore.collection('restaurants').get();
  final cat = sdLibNormalizeExploreCategoryId(categoryId);
  final filtered = docs.docs.where((d) {
    final m = d.data();
    if (!restaurantCityMatchesUserExplore(cityKey, m)) {
      return false;
    }
    if (cat != null && (m['restaurantCategory'] as String?) != cat) {
      return false;
    }
    if (openNowOnly && !isRestaurantOpenNow(m)) {
      return false;
    }
    return true;
  }).toList();
  filtered.sort((a, b) {
    final na = (a.data()['restaurantName'] ?? a.data()['name'] ?? '')
        .toString()
        .toLowerCase();
    final nb = (b.data()['restaurantName'] ?? b.data()['name'] ?? '')
        .toString()
        .toLowerCase();
    return na.compareTo(nb);
  });

  if (offset >= filtered.length) {
    return const RestaurantNamePage(names: [], hasMore: false, total: 0);
  }
  final chunk = filtered.skip(offset).take(limit).toList();
  final names = chunk
      .map(
        (d) => (d.data()['restaurantName'] ?? d.data()['name'] ?? '')
            .toString()
            .trim(),
      )
      .where((n) => n.isNotEmpty)
      .toList();
  final hasMore = offset + chunk.length < filtered.length;
  return RestaurantNamePage(
    names: names,
    hasMore: hasMore,
    total: filtered.length,
  );
}

/// Spoken list of [names] with short pauses between entries (better for TTS).
String formatExploreNamesForTts(List<String> names) {
  if (names.isEmpty) return '';
  return names.join('. ');
}

Future<String> ttsLineForExploreCategoryFilter({
  required String categoryId,
  required String categoryLabel,
}) async {
  final page = await fetchRestaurantNamesForVoice(
    categoryId: categoryId,
    offset: 0,
    limit: 40,
    openNowOnly: true,
  );
  if (page == null) {
    return 'Selected category $categoryLabel. Set your city in Profile if you do not see restaurants.';
  }
  if (page.total == 0) {
    return 'With open now on — only places open at this hour, using your times on file — '
        'no restaurants in category $categoryLabel match. '
        'Try another category or turn off open now on the filter sheet.';
  }
  const maxSpoken = 12;
  final spoken = page.names.take(maxSpoken).toList();
  final list = formatExploreNamesForTts(spoken);
  final unsaid = page.total - spoken.length;
  final tail = unsaid > 0 ? '. $unsaid more are on your screen.' : '';
  return 'Open now is on. Restaurants with category $categoryLabel that are open right now are: '
      '$list$tail';
}

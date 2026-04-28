/// SD-lib: fixed restaurant type taxonomy (registration + home UI).
///
/// Store [SdLibRestaurantCategory.id] in Firestore field `restaurantCategory`.
class SdLibRestaurantCategory {
  const SdLibRestaurantCategory({required this.id, required this.label});

  final String id;
  final String label;
}

const List<SdLibRestaurantCategory> kSdLibRestaurantCategories = [
  SdLibRestaurantCategory(id: 'desi', label: 'Desi'),
  SdLibRestaurantCategory(id: 'fast_food', label: 'Fast Food'),
  SdLibRestaurantCategory(id: 'cafe', label: 'Cafe and Coffee'),
  SdLibRestaurantCategory(id: 'bakery', label: 'Bakery & Pastry'),
  SdLibRestaurantCategory(id: 'pizza', label: 'Pizza & Italian'),
  SdLibRestaurantCategory(id: 'asian', label: 'Asian'),
  SdLibRestaurantCategory(id: 'bbq_grill', label: 'BBQ & Grill'),
  SdLibRestaurantCategory(id: 'seafood', label: 'Seafood'),
  SdLibRestaurantCategory(id: 'healthy', label: 'Healthy & Salads'),
  SdLibRestaurantCategory(id: 'desserts', label: 'Desserts & Ice Cream'),
  SdLibRestaurantCategory(id: 'bar_pub', label: 'Bar & Pub'),
  SdLibRestaurantCategory(id: 'fine_dining', label: 'Fine Dining'),
  SdLibRestaurantCategory(id: 'street_food', label: 'Street Food'),
  SdLibRestaurantCategory(id: 'other', label: 'Other'),
];

String? sdLibRestaurantCategoryLabel(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final c in kSdLibRestaurantCategories) {
    if (c.id == id) return c.label;
  }
  return id;
}

/// Explore/home filter: [null] means every category. Normalizes empty strings,
/// aliases like "all", and unknown ids so the list is not accidentally cleared.
String? sdLibNormalizeExploreCategoryId(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower == 'all' ||
      lower == 'any' ||
      lower == 'everything' ||
      lower == 'clear') {
    return null;
  }
  for (final c in kSdLibRestaurantCategories) {
    if (c.id == trimmed || c.id.toLowerCase() == lower) return c.id;
  }
  return null;
}

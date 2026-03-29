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
  SdLibRestaurantCategory(id: 'cafe', label: 'Café & Coffee'),
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

/// High-level intent for food / ordering / in-app customer flows.
enum VoiceIntentKind {
  /// Clearly not about food, restaurants, or this app.
  nonFood,

  /// Heard something but could not map to a specific flow.
  unknown,

  /// Hours, address, location, "about" a place.
  restaurantInfo,

  /// Dish details: ingredients, spicy, what is X, price of item.
  dishDescription,

  /// Browse by cuisine / SD-lib category (Desi, Pizza, …).
  categoryBrowse,

  /// User's own account: name, address, orders, payments.
  userProfile,

  /// Cart, checkout, pay, place order, add to cart.
  orderPlacement,
}

/// Output of [VoiceIntentClassifier] after final STT text is available.
class VoiceIntentResult {
  const VoiceIntentResult({
    required this.kind,
    required this.isFoodOrOrderingRelated,
    this.confidence = 0.5,
    this.extractedQuery,
    this.restaurantName,
    this.itemName,
    this.categoryId,
  });

  final VoiceIntentKind kind;

  /// True when utterance is plausibly about food, ordering, restaurants, or in-app customer data.
  final bool isFoodOrOrderingRelated;

  /// Rough 0–1 score from the rule engine (not ML-calibrated).
  final double confidence;

  /// Free-text snippet for search or follow-up (e.g. dish name, restaurant fragment).
  final String? extractedQuery;

  final String? restaurantName;
  final String? itemName;

  /// When [kind] == [VoiceIntentKind.categoryBrowse], matches [SdLibRestaurantCategory.id].
  final String? categoryId;

  static const VoiceIntentResult empty = VoiceIntentResult(
    kind: VoiceIntentKind.unknown,
    isFoodOrOrderingRelated: false,
    confidence: 0,
  );
}

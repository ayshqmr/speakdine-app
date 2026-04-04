/// Voice intents focused on add-to-cart flow, safe checkout, settings, and recovery.
enum VoiceIntentKind {
  // system
  nonFood,
  unknown,
  cancelAction,

  // add to cart flow
  addToCartRequest,
  selectMenuItem,
  confirmAddToCart,

  // cart
  openCartIntent,

  /// Multi-clause edits, e.g. "add one more coffee and remove sandwich".
  cartNaturalLanguageEdit,

  // order safety (never auto-submits payment)
  initiateCheckout,
  confirmOrderUIOnly,
  cancelCheckout,

  // settings
  openSettings,
  toggleSetting,
  updateSettingValue,

  // disambiguation
  addToCartIntent,
  ambiguousOrderIntent,

  // navigation
  goHome,
  goBack,
  whereAmI,

  /// Open live order tracking for the latest active order and speak status + ETA.
  trackOrderIntent,

  // guidance
  suggestNextAction,
  clarifyUserIntent,
  cancelCurrentFlow,
}

/// Output of classifiers after STT (or LLM) text is available.
class VoiceIntentResult {
  const VoiceIntentResult({
    required this.kind,
    required this.isFoodOrOrderingRelated,
    this.confidence = 0.5,
    this.extractedQuery,
    this.restaurantName,
    this.itemName,
    this.categoryId,
    this.settingKey,
    this.settingValue,
  });

  final VoiceIntentKind kind;

  final bool isFoodOrOrderingRelated;

  final double confidence;

  final String? extractedQuery;

  final String? restaurantName;

  final String? itemName;

  /// SD-lib restaurant category id when narrowing browse.
  final String? categoryId;

  /// For [toggleSetting] / [updateSettingValue], e.g. notifications, location, username.
  final String? settingKey;

  final String? settingValue;

  /// Internal: [suggestNextAction] repeats last TTS when set to this value.
  static const String suggestRepeatLast = '__repeat_last__';

  static const VoiceIntentResult empty = VoiceIntentResult(
    kind: VoiceIntentKind.unknown,
    isFoodOrOrderingRelated: false,
    confidence: 0,
  );
}

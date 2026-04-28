import 'package:flutter/widgets.dart';

/// Hooks registered by customer UI so voice commands can drive navigation/state
/// without tight coupling to widgets.
class CustomerVoiceBridge {
  CustomerVoiceBridge._();
  static final CustomerVoiceBridge instance = CustomerVoiceBridge._();

  void Function(String query)? applySearchQuery;
  void Function(String? categoryId)? applyCategoryId;

  /// Returns true if a detail screen was opened.
  Future<bool> Function(String name)? openRestaurantByName;

  /// Updates Firestore + login lookup from voice; returns null on success, or short error for TTS.
  Future<String?> Function(String spokenNewName)? updateCustomerDisplayName;

  /// [CustomerShell] BuildContext for pushes (logout, notifications, settings).
  BuildContext? shellContext;

  /// Pop inner restaurant stack route if possible.
  VoidCallback? popRestaurantRoute;

  /// Pop restaurant stack to root (browse list).
  VoidCallback? resetRestaurantStack;

  /// Ask [UserHomeView] to open the explore filter sheet (async).
  Future<void> Function()? openExploreFilters;

  /// Apply sort key: rating | price_low | price_high | name | default
  void Function(String sortKey)? applyRestaurantSort;

  /// [CustomerShell] rebuild when cart changes from voice.
  VoidCallback? notifyCartChanged;

  /// Open edit-profile bottom sheet (customer profile tab).
  VoidCallback? openCustomerEditProfile;

  /// Push saved cards / payments UI from profile.
  VoidCallback? openCustomerPaymentsPage;

  /// Trigger profile photo flow.
  VoidCallback? pickCustomerProfilePhoto;

  /// Open map / address dialog (customer profile).
  VoidCallback? openCustomerAddressPicker;

  /// Short human-readable hint for [whereAmI] (e.g. tab + screen).
  String Function()? describeVoiceLocation;

  /// Rich context for the SpeakTime conversational LLM (tab, cart, menu text).
  String Function()? buildVoiceAssistantContextForLlm;

  /// Set while [RestaurantDetailView] is showing; cleared when leaving.
  String? restaurantMenuVoiceSummary;

  /// Category + description for SpeakTime while a restaurant menu is open.
  String? restaurantVoiceProfileSummary;

  /// Latest reviews (up to 3) as TTS-friendly lines while a menu is open.
  String? restaurantVoiceReviewsSummary;

  /// Full first-visit script: name, category, description, then "Would you like… reviews?"
  String? restaurantMenuIntroSpeech;

  /// Set true after [restaurantMenuIntroSpeech] is read once (skipped for tab-jump commands).
  bool restaurantVoiceMenuIntroShown = false;

  /// True after the menu intro asks whether to hear reviews, until the user hears them or declines.
  /// Used so "yes" still works after [assistantSpeechLine] is overwritten by the same-turn LLM reply.
  bool voiceAwaitingRestaurantReviewsYesNo = false;

  /// After listing restaurant names, assistant asked for a cuisine — "yes" needs a hint, not silence.
  bool voiceAwaitingBrowseCuisineHint = false;

  /// After add-to-cart or cart NL, assistant asked "add/anything else?".
  bool voiceAwaitingCartAddMorePrompt = false;

  /// After [openCartIntent] line: place order vs make changes.
  bool voiceAwaitingCartOrderOrChangesPrompt = false;

  /// After empty-cart line offering browse or search.
  bool voiceAwaitingEmptyCartBrowsePrompt = false;

  /// After successful add-to-cart, awaiting yes/no for customization.
  bool voiceAwaitingCustomizeYesNo = false;

  /// Waiting for free-text customization note to save for [pendingVoiceCustomizationItem].
  bool voiceAwaitingCustomizationText = false;

  /// Item name currently targeted for customization note updates.
  String? pendingVoiceCustomizationItem;

  /// Awaiting item name after "remove customization" without a target item.
  bool voiceAwaitingRemoveCustomizationItem = false;

  /// Dish name (or search phrase) the user asked to add; cleared after confirm or cancel flow.
  String? pendingVoiceCartItem;

  /// [RestaurantDetailView] only: match [pendingVoiceCartItem] to loaded menu and add.
  /// Returns `null` on success, or a short error phrase for TTS.
  Future<String?> Function()? confirmVoiceAddToCartFromMenu;

  /// Opens a pending delivered-order review dialog, if available.
  /// Returns `null` on success, or a short error phrase for TTS.
  Future<String?> Function()? openPendingReviewDialog;

  /// True while review dialog is currently shown and voice hooks are active.
  bool Function()? isVoiceReviewDialogOpen;

  /// Set star rating (1..5) in active review dialog.
  void Function(int stars)? setVoiceReviewStars;

  /// Set optional comment in active review dialog.
  void Function(String comment)? setVoiceReviewComment;

  /// Submit active review dialog using existing onPressed flow.
  Future<String?> Function()? submitVoiceReview;

  /// Cancel active review dialog.
  void Function()? cancelVoiceReview;

  /// Read full cart summary with quantities for voice playback.
  String Function()? voiceFullCartSummary;

  /// Place order from voice with `cod` or `online`.
  /// Returns null on success, or short error phrase for TTS.
  Future<String?> Function(String method)? placeVoiceOrderWithPayment;

  /// Same as tapping **Place Order** on the cart (opens payment method UI).
  void Function()? showCartPaymentMethodDialog;

  /// True while the cart payment method dialog is on screen.
  bool paymentMethodDialogVisible = false;

  /// After "place order" / [initiateCheckout], we accept COD vs online on the next utterance.
  bool voiceExpectingCheckoutPayment = false;

  /// [CustomerShell] wires these so overlays (e.g. payment dialog) can use the same mic as the FAB.
  void Function()? voiceMicHoldStart;
  void Function()? voiceMicHoldEnd;

  /// Opens tracking for the latest active order; returns full line for TTS.
  Future<String?> Function()? openActiveOrderTracking;

  /// [CustomerShell] reads description + asks about reviews when a menu opens.
  Future<void> Function()? playRestaurantDetailVoiceIntro;

  /// Display name for [playRestaurantDetailVoiceIntro] (set by [RestaurantDetailView]).
  String? restaurantVoiceDetailDisplayName;

  /// Plain category label and description for auto intro TTS.
  String? restaurantVoiceCategoryPlain;
  String? restaurantVoiceDescriptionPlain;

  /// [RestaurantDetailView]: TTS for full menu or one section ([categoryKey]: appetizer, main, dessert, drink).
  String? Function({String? categoryKey})? speakableMenuItemsForVoice;

  /// [RestaurantDetailView]: answer "burger price" / "pizza description" from loaded menu docs.
  String? Function(String utterance)? answerMenuItemVoiceFact;

  void clearPendingVoiceCartItem() {
    pendingVoiceCartItem = null;
  }

  /// Latest speech-to-text while holding the mic (and final line after release).
  final ValueNotifier<String> userSpeechLine = ValueNotifier<String>('');

  /// Last phrase the assistant spoke via TTS after a hold session.
  final ValueNotifier<String> assistantSpeechLine = ValueNotifier<String>('');

  /// True while the customer is holding the voice FAB (listening).
  final ValueNotifier<bool> voiceListening = ValueNotifier<bool>(false);

  /// Payment method dialog is open — do not start speech recognition.
  bool voiceAssistantPaused = false;

  void clear() {
    applySearchQuery = null;
    applyCategoryId = null;
    openRestaurantByName = null;
    updateCustomerDisplayName = null;
    shellContext = null;
    popRestaurantRoute = null;
    resetRestaurantStack = null;
    openExploreFilters = null;
    applyRestaurantSort = null;
    notifyCartChanged = null;
    openCustomerEditProfile = null;
    openCustomerPaymentsPage = null;
    pickCustomerProfilePhoto = null;
    openCustomerAddressPicker = null;
    describeVoiceLocation = null;
    buildVoiceAssistantContextForLlm = null;
    restaurantMenuVoiceSummary = null;
    restaurantVoiceProfileSummary = null;
    restaurantVoiceReviewsSummary = null;
    restaurantMenuIntroSpeech = null;
    restaurantVoiceMenuIntroShown = false;
    voiceAwaitingRestaurantReviewsYesNo = false;
    voiceAwaitingBrowseCuisineHint = false;
    voiceAwaitingCartAddMorePrompt = false;
    voiceAwaitingCartOrderOrChangesPrompt = false;
    voiceAwaitingEmptyCartBrowsePrompt = false;
    voiceAwaitingCustomizeYesNo = false;
    voiceAwaitingCustomizationText = false;
    pendingVoiceCustomizationItem = null;
    voiceAwaitingRemoveCustomizationItem = false;
    pendingVoiceCartItem = null;
    confirmVoiceAddToCartFromMenu = null;
    openPendingReviewDialog = null;
    isVoiceReviewDialogOpen = null;
    setVoiceReviewStars = null;
    setVoiceReviewComment = null;
    submitVoiceReview = null;
    cancelVoiceReview = null;
    voiceFullCartSummary = null;
    placeVoiceOrderWithPayment = null;
    showCartPaymentMethodDialog = null;
    paymentMethodDialogVisible = false;
    voiceExpectingCheckoutPayment = false;
    voiceMicHoldStart = null;
    voiceMicHoldEnd = null;
    openActiveOrderTracking = null;
    playRestaurantDetailVoiceIntro = null;
    restaurantVoiceDetailDisplayName = null;
    restaurantVoiceCategoryPlain = null;
    restaurantVoiceDescriptionPlain = null;
    speakableMenuItemsForVoice = null;
    answerMenuItemVoiceFact = null;
    voiceAssistantPaused = false;
  }

  void clearSpeechLines() {
    userSpeechLine.value = '';
    assistantSpeechLine.value = '';
  }
}

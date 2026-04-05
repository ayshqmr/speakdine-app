import 'dart:async' show unawaited;

import 'package:speak_dine/services/speech_to_text_service.dart';
import 'package:speak_dine/services/text_to_speech_service.dart';
import 'package:speak_dine/constants/menu_dish_category.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/voice/conversational_assistant_service.dart';
import 'package:speak_dine/voice/explore_restaurant_voice.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/voice/gemini_intent_service.dart';
import 'package:speak_dine/voice/speaktime_assistant_system_prompt.dart';
import 'package:speak_dine/voice/voice_intent_classifier.dart';
import 'package:speak_dine/voice/voice_intent_models.dart';
import 'package:speak_dine/voice/voice_intent_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:speak_dine/view/user/review_dialog.dart';

enum _VoiceReviewStage {
  idle,
  askStars,
  askCommentConsent,
  captureComment,
  askSubmitOrCancel,
}

/// Hold-to-talk: listen while the mic is held; on release run intent + TTS once.
class VoiceAssistantSession {
  VoiceAssistantSession({
    required void Function(int tabIndex) switchToTab,
    this.onMicNotReady,
    this.onCouldNotStartListening,
  }) : _switchToTab = switchToTab {
    _router = VoiceIntentRouter(switchToTab: _switchToTab, tts: _tts);
  }

  final void Function(int tabIndex) _switchToTab;
  final void Function()? onMicNotReady;
  final void Function()? onCouldNotStartListening;
  final SpeechToTextService _stt = SpeechToTextService();
  final TextToSpeechService _tts = TextToSpeechService();
  late final VoiceIntentRouter _router;
  final VoiceIntentClassifier _classifier = const VoiceIntentClassifier();
  final GeminiIntentService _gemini = const GeminiIntentService();
  final ConversationalAssistantService _conversational =
      const ConversationalAssistantService();

  bool _initialized = false;
  bool _holding = false;
  String _latestText = '';
  _VoiceReviewStage _reviewStage = _VoiceReviewStage.idle;
  bool _restaurantBrowseActive = false;
  int _restaurantBrowseOffset = 0;
  String? _restaurantBrowseCategoryId;
  bool _filterBrowseActive = false;
  int _filterBrowseOffset = 0;

  bool get isHolding => _holding;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = await _stt.init();
  }

  /// Opening line for blind users when the customer shell first appears.
  Future<void> playSpeaktimeWelcomeOnce() async {
    await _tts.stop();
    await _tts.speak(kSpeaktimeWelcomeTts);
    _applyAssistantSpeechLine(kSpeaktimeWelcomeTts);
  }

  /// When a restaurant menu opens: speak description (client TTS, no LLM), then ask
  /// about reviews. Sets [voiceAwaitingRestaurantReviewsYesNo] for the next utterance.
  Future<void> playRestaurantDetailVoiceIntro() async {
    final bridge = CustomerVoiceBridge.instance;
    if (bridge.confirmVoiceAddToCartFromMenu == null) {
      return;
    }
    if (bridge.voiceAssistantPaused) {
      return;
    }
    await _tts.stop();

    final name = (bridge.restaurantVoiceDetailDisplayName ?? 'This restaurant')
        .trim();
    final cat = bridge.restaurantVoiceCategoryPlain?.trim();
    final desc = bridge.restaurantVoiceDescriptionPlain?.trim();

    final about = StringBuffer()
      ..write(name)
      ..write('. ');
    if (cat != null && cat.isNotEmpty) {
      about.write('Category: $cat. ');
    }
    if (desc != null && desc.isNotEmpty) {
      about.write('Description: ');
      about.write(desc);
    } else {
      about.write('There is no description for this place yet.');
    }
    final aboutLine = about.toString();
    await _tts.speak(aboutLine);

    const question = 'Would you like to hear the latest reviews?';
    await _tts.speak(question);

    final fullLine = '$aboutLine $question';
    _applyAssistantSpeechLine(fullLine);
    bridge.restaurantVoiceMenuIntroShown = true;
    bridge.voiceAwaitingRestaurantReviewsYesNo = true;
  }

  Future<void> onHoldStart() async {
    await ensureInitialized();
    final bridge = CustomerVoiceBridge.instance;
    if (!_initialized) {
      bridge.voiceListening.value = false;
      onMicNotReady?.call();
      return;
    }

    if (bridge.voiceAssistantPaused) {
      await _tts.stop();
      const msg =
          'Voice control is paused while you confirm payment on the screen. Please use the screen.';
      await _tts.speak(msg);
      _applyAssistantSpeechLine(msg);
      bridge.voiceListening.value = false;
      return;
    }

    if (_holding) return;
    _holding = true;
    bridge.voiceListening.value = true;
    bridge.assistantSpeechLine.value = '';
    _latestText = '';
    bridge.userSpeechLine.value = '';

    await _stt.cancelListening();
    await _tts.stop();

    final started = await _stt.startListening(
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 10),
      onResultText: (text, isFinal) {
        _latestText = text;
        bridge.userSpeechLine.value = text;
        debugPrint(
          '[VoiceSTT] ${isFinal ? "final" : "partial"}: ${text.trim()}',
        );
      },
    );
    if (!started) {
      _holding = false;
      bridge.voiceListening.value = false;
      onCouldNotStartListening?.call();
    }
  }

  Future<void> onHoldEnd() async {
    final bridge = CustomerVoiceBridge.instance;
    if (!_holding) return;
    _holding = false;
    bridge.voiceListening.value = false;

    await _stt.stopListening();

    final text = _latestText.trim();
    debugPrint('[VoiceSTT] hold-end text="$text"');
    bridge.userSpeechLine.value = text;
    if (text.isEmpty) {
      debugPrint('[VoiceSTT] no speech captured');
      return;
    }

    await _maybeSpeakRestaurantMenuIntro(text);

    final reviewHandled = await _handleReviewVoiceFlow(text);
    if (reviewHandled != null) {
      await _tts.stop();
      await _tts.speak(reviewHandled);
      _applyAssistantSpeechLine(reviewHandled);
      return;
    }

    final onRestaurantMenu = bridge.confirmVoiceAddToCartFromMenu != null;
    if (onRestaurantMenu) {
      final factLine = bridge.answerMenuItemVoiceFact?.call(text);
      if (factLine != null) {
        await _tts.stop();
        await _tts.speak(factLine);
        _applyAssistantSpeechLine(factLine);
        return;
      }
    }

    final menuListHandled = _handleRestaurantMenuListingVoice(text);
    if (menuListHandled != null) {
      await _tts.stop();
      await _tts.speak(menuListHandled);
      _applyAssistantSpeechLine(menuListHandled);
      return;
    }

    final navShortcut = VoiceIntentRouter.classifyVoiceTabShortcut(
      text,
      onRestaurantMenu: onRestaurantMenu,
    );
    if (navShortcut != VoiceTabShortcut.none) {
      await _tts.stop();
      final navLine = await _router.voiceTabShortcutLine(navShortcut);
      await _tts.speak(navLine);
      _applyAssistantSpeechLine(navLine);
      return;
    }

    final reviewsHandled = _handleRestaurantReviewsVoiceFlow(text);
    if (reviewsHandled != null) {
      await _tts.stop();
      await _tts.speak(reviewsHandled);
      _applyAssistantSpeechLine(reviewsHandled);
      return;
    }

    final browseCuisineFollowUp = _handleBrowseCuisineFollowUp(text);
    if (browseCuisineFollowUp != null) {
      await _tts.stop();
      await _tts.speak(browseCuisineFollowUp);
      _applyAssistantSpeechLine(browseCuisineFollowUp);
      return;
    }

    final cartFollowUp = _handleCartVoicePromptFollowUps(text);
    if (cartFollowUp != null) {
      await _tts.stop();
      await _tts.speak(cartFollowUp);
      _applyAssistantSpeechLine(cartFollowUp);
      return;
    }

    final filterPick = await _handleFilterCategoryPick(text);
    if (filterPick != null) {
      await _tts.stop();
      await _tts.speak(filterPick);
      _applyAssistantSpeechLine(filterPick);
      return;
    }

    final filterHandled = await _handleFilterVoiceFlow(text);
    if (filterHandled != null) {
      await _tts.stop();
      await _tts.speak(filterHandled);
      _applyAssistantSpeechLine(filterHandled);
      return;
    }

    final checkoutHandled = await _handleCheckoutVoiceFlow(text);
    if (checkoutHandled != null) {
      await _tts.stop();
      await _tts.speak(checkoutHandled);
      _applyAssistantSpeechLine(checkoutHandled);
      return;
    }

    final browseHandled = await _handleRestaurantBrowseFlow(text);
    if (browseHandled != null) {
      await _tts.stop();
      await _tts.speak(browseHandled);
      _applyAssistantSpeechLine(browseHandled);
      return;
    }

    final ctx =
        bridge.buildVoiceAssistantContextForLlm?.call() ??
        'No detailed screen context.';

    final turn = await _conversational.process(
      userUtterance: text,
      situationalContext: ctx,
    );

    if (turn != null) {
      var spoken = turn.speech;
      _router.speakAloud = false;
      try {
        // Menu price/description: authoritative match from loaded menu docs must win
        // over LLM speech or intents like addToCartRequest ("burger price").
        String? menuFact;
        if (text.trim().isNotEmpty &&
            bridge.confirmVoiceAddToCartFromMenu != null) {
          menuFact = bridge.answerMenuItemVoiceFact?.call(text);
        }
        if (menuFact != null && menuFact.trim().isNotEmpty) {
          spoken = menuFact.trim();
        } else if (turn.intent != null) {
          final routerLine = await _router.handle(
            turn.intent!,
            userUtterance: text,
          );
          spoken = routerLine;
        }
      } finally {
        _router.speakAloud = true;
      }
      await _tts.stop();
      await _tts.speak(spoken);
      _applyAssistantSpeechLine(spoken);
      return;
    }

    final intent = await _resolveVoiceIntent(text);
    debugPrint(
      '[VoiceIntent] kind=${intent.kind} confidence=${intent.confidence}',
    );
    final spoken = await _router.handle(intent, userUtterance: text);
    _applyAssistantSpeechLine(spoken);
  }

  /// Prefer high-confidence rule-based intents over Gemini when the cloud
  /// model returns [unknown] — fixes phrases like "place my order".
  Future<VoiceIntentResult> _resolveVoiceIntent(String text) async {
    final rule = _classifier.classify(text);
    final cloud = await _gemini.classify(text);
    if (rule.confidence >= 0.75 && rule.kind != VoiceIntentKind.unknown) {
      return rule;
    }
    return cloud ?? rule;
  }

  Future<String?> _handleReviewVoiceFlow(String text) async {
    final bridge = CustomerVoiceBridge.instance;
    final lower = text.toLowerCase();

    bool hasWord(List<String> words) => words.any(lower.contains);
    bool isYes() =>
        hasWord(['yes', 'yeah', 'yep', 'sure', 'okay', 'ok', 'haan']);
    bool isNo() => hasWord(['no', 'nope', 'nah', 'skip', 'nahi']);

    if (_reviewStage == _VoiceReviewStage.idle) {
      final wantsReview = _utteranceWantsRateAndReviewFlow(lower);
      if (!wantsReview) {
        return null;
      }
      final err = await _openPendingReviewDialogForVoice(bridge);
      if (err != null) {
        return err;
      }
      _reviewStage = _VoiceReviewStage.askStars;
      return 'Opening rate and review for your latest delivered order. '
          'How many stars would you like to give, from zero to five?';
    }

    final isDialogOpen = bridge.isVoiceReviewDialogOpen?.call() == true;
    if (!isDialogOpen) {
      _reviewStage = _VoiceReviewStage.idle;
      return null;
    }

    switch (_reviewStage) {
      case _VoiceReviewStage.askStars:
        final stars = _extractStarValue(lower);
        if (stars == null) {
          return 'Please say a number from zero to five stars.';
        }
        bridge.setVoiceReviewStars?.call(stars);
        _reviewStage = _VoiceReviewStage.askCommentConsent;
        return 'Got it, $stars stars. Would you like to add a comment?';

      case _VoiceReviewStage.askCommentConsent:
        if (isYes()) {
          _reviewStage = _VoiceReviewStage.captureComment;
          return 'Please say your comment now.';
        }
        if (isNo()) {
          final err = await bridge.submitVoiceReview?.call();
          if (err != null) {
            return '$err You can say yes to add a comment, or try again.';
          }
          _reviewStage = _VoiceReviewStage.idle;
          return 'Your review has been submitted. Thank you for your feedback.';
        }
        return 'Please say yes to add a comment, or no to submit without a comment.';

      case _VoiceReviewStage.captureComment:
        final comment = text.trim();
        if (comment.isEmpty) {
          return 'I did not catch the comment. Please say your comment again.';
        }
        bridge.setVoiceReviewComment?.call(comment);
        _reviewStage = _VoiceReviewStage.askSubmitOrCancel;
        return 'Comment added. Would you like to submit or cancel this review?';

      case _VoiceReviewStage.askSubmitOrCancel:
        if (hasWord([
          'submit',
          'post',
          'send',
          'done',
          'confirm',
          'select',
        ])) {
          final err = await bridge.submitVoiceReview?.call();
          _reviewStage = _VoiceReviewStage.idle;
          if (err != null) {
            return '$err Say submit or select to try again, or cancel.';
          }
          return 'Your review has been submitted. Thank you for your feedback.';
        }
        if (hasWord(['cancel', 'close', 'stop', 'discard'])) {
          bridge.cancelVoiceReview?.call();
          _reviewStage = _VoiceReviewStage.idle;
          return 'Review cancelled.';
        }
        return 'Please say submit or select to post your review, or cancel to close it.';

      case _VoiceReviewStage.idle:
        return null;
    }
  }

  bool _utteranceWantsRateAndReviewFlow(String lower) {
    bool has(String w) => lower.contains(w);
    if (has('rate and review') ||
        has('rate & review') ||
        has('rate n review')) {
      return true;
    }
    if (has('leave a review') ||
        has('write a review') ||
        has('give a review') ||
        has('submit a review')) {
      return true;
    }
    if ((has('review') ||
            has('rate') ||
            has('rating') ||
            has('feedback')) &&
        (has('yes') ||
            has('yeah') ||
            has('yep') ||
            has('sure') ||
            has('okay') ||
            has('ok') ||
            has('haan') ||
            has('add') ||
            has('leave') ||
            has('write') ||
            has('open') ||
            has('submit'))) {
      return true;
    }
    return false;
  }

  Future<String?> _openPendingReviewDialogForVoice(CustomerVoiceBridge bridge) async {
    final registered = bridge.openPendingReviewDialog;
    if (registered != null) {
      return registered();
    }
    final ctx = bridge.shellContext;
    final user = FirebaseAuth.instance.currentUser;
    if (ctx == null || !ctx.mounted || user == null) {
      return 'Please sign in, then open the Orders tab and try again.';
    }
    try {
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('orders')
          .orderBy('createdAt', descending: true)
          .limit(40)
          .get();
      for (final doc in qs.docs) {
        final data = doc.data();
        final status = (data['status'] as String? ?? '').trim();
        if (status != 'delivered') continue;
        if (data['reviewed'] == true) continue;
        final rid = (data['restaurantId'] as String?)?.trim() ?? '';
        if (rid.isEmpty) continue;
        if (!ctx.mounted) return 'Try again in a moment.';
        showReviewDialog(
          ctx,
          restaurantId: rid,
          restaurantName:
              (data['restaurantName'] as String?)?.trim() ?? 'Restaurant',
          orderId: doc.id,
          customerId: user.uid,
          customerName:
              (data['customerName'] as String?)?.trim() ?? 'Customer',
        );
        return null;
      }
    } catch (e, st) {
      debugPrint('[VoiceReview] open dialog: $e\n$st');
      return 'Could not load orders. Open the Orders tab and try again.';
    }
    return 'You do not have any delivered order pending review.';
  }

  int? _extractStarValue(String lower) {
    if (RegExp(r'\b5\b').hasMatch(lower) ||
        lower.contains('five') ||
        lower.contains('five star') ||
        lower.contains('5 star')) {
      return 5;
    }
    if (RegExp(r'\b4\b').hasMatch(lower) ||
        lower.contains('four') ||
        lower.contains('four star') ||
        lower.contains('4 star')) {
      return 4;
    }
    if (RegExp(r'\b3\b').hasMatch(lower) ||
        lower.contains('three') ||
        lower.contains('three star') ||
        lower.contains('3 star')) {
      return 3;
    }
    if (RegExp(r'\b2\b').hasMatch(lower) ||
        lower.contains('two') ||
        lower.contains('two star') ||
        lower.contains('2 star')) {
      return 2;
    }
    if (RegExp(r'\b1\b').hasMatch(lower) ||
        lower.contains('one') ||
        lower.contains('one star') ||
        lower.contains('1 star')) {
      return 1;
    }
    if (RegExp(r'\b0\b').hasMatch(lower) ||
        lower.contains('zero') ||
        lower.contains('zero star') ||
        lower.contains('0 star')) {
      return 0;
    }
    return null;
  }

  /// Derive which yes-or-no follow-ups match the last assistant line (cart, browse, etc.).
  void _syncVoicePromptFlagsFromAssistantSpeech(String spoken) {
    final b = CustomerVoiceBridge.instance;
    final t = spoken.trim();
    if (t.isEmpty) {
      return;
    }
    final l = t.toLowerCase();
    b.voiceAwaitingBrowseCuisineHint =
        l.contains('specific cuisine like fast food');
    b.voiceAwaitingCartAddMorePrompt = l.contains('add something else') ||
        (l.contains('would you like') && l.contains('anything else'));
    b.voiceAwaitingCartOrderOrChangesPrompt =
        l.contains('place your order') && l.contains('make changes');
    b.voiceAwaitingEmptyCartBrowsePrompt =
        l.contains('cart is empty') && l.contains('browse restaurants');
  }

  void _applyAssistantSpeechLine(String spoken) {
    final t = spoken.trim();
    CustomerVoiceBridge.instance.assistantSpeechLine.value = t;
    _syncVoicePromptFlagsFromAssistantSpeech(t);
  }

  bool _isAffirmationOnlyUtterance(String raw) {
    var t = raw.toLowerCase().trim();
    if (t.isEmpty) {
      return false;
    }
    if (!_isAffirmativeHearReviews(t)) {
      return false;
    }
    for (final w in [
      'yes',
      'yeah',
      'yep',
      'sure',
      'okay',
      'ok',
      'please',
      'haan',
    ]) {
      t = t.replaceAll(RegExp('\\b${RegExp.escape(w)}\\b'), ' ');
    }
    t = t
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length < 2;
  }

  bool _isDeclineOnlyUtterance(String raw) {
    var t = raw.toLowerCase().trim();
    if (t.isEmpty) {
      return false;
    }
    if (!_isDeclineHearReviews(t)) {
      return false;
    }
    t = t.replaceAll('not now', ' ');
    t = t.replaceAll('no thanks', ' ');
    t = t.replaceAll('no thank you', ' ');
    t = t.replaceAll('do not', ' ');
    t = t.replaceAll("don't", ' ');
    for (final w in [
      'no',
      'nope',
      'nah',
      'nahi',
      'skip',
      'later',
    ]) {
      t = t.replaceAll(RegExp('\\b${RegExp.escape(w)}\\b'), ' ');
    }
    t = t
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length < 2;
  }

  String? _handleBrowseCuisineFollowUp(String text) {
    final bridge = CustomerVoiceBridge.instance;
    if (!bridge.voiceAwaitingBrowseCuisineHint) {
      return null;
    }
    final lower = text.toLowerCase().trim();
    if (RegExp(r'\b(tell|give)\s+more\b').hasMatch(lower) ||
        RegExp(r'\bmore\s+names\b').hasMatch(lower)) {
      return null;
    }
    if (_detectCategoryId(lower) != null) {
      return null;
    }
    if (RegExp(r'(?:open|go to)\s+\S').hasMatch(lower)) {
      return null;
    }
    if (_isAffirmativeHearReviews(lower) && _isAffirmationOnlyUtterance(text)) {
      return 'Try naming a cuisine, for example fast food, coffee, Pakistani, or barbecue. '
          'Or say tell more for more restaurant names, or say open followed by a restaurant name.';
    }
    if (_isDeclineHearReviews(lower) && _isDeclineOnlyUtterance(text)) {
      return 'No problem. Say tell more for more names, say open with a restaurant name, or say go home.';
    }
    return null;
  }

  String? _handleCartVoicePromptFollowUps(String text) {
    final bridge = CustomerVoiceBridge.instance;
    final lower = text.toLowerCase().trim();
    final affirmOnly =
        _isAffirmativeHearReviews(lower) && _isAffirmationOnlyUtterance(text);
    final declineOnly =
        _isDeclineHearReviews(lower) && _isDeclineOnlyUtterance(text);

    if (bridge.voiceAwaitingEmptyCartBrowsePrompt) {
      if (affirmOnly) {
        _switchToTab(VoiceIntentRouter.tabHome);
        bridge.resetRestaurantStack?.call();
        return 'Okay. Here is the home list. Say search for a dish, or ask for restaurant names.';
      }
      if (declineOnly) {
        return 'All right. Open a restaurant, add items, then say open cart when you are ready.';
      }
    }
    if (bridge.voiceAwaitingCartAddMorePrompt) {
      if (affirmOnly) {
        return 'Great. Say add followed by the dish name, for example add burger to cart. '
            'Or say open cart to review your order.';
      }
      if (declineOnly) {
        return 'Okay. Say open cart to check out, or keep browsing the menu.';
      }
    }
    if (bridge.voiceAwaitingCartOrderOrChangesPrompt) {
      if (lower.contains('change') ||
          lower.contains('edit') ||
          RegExp(r'\bremove\b').hasMatch(lower)) {
        return 'Say remove or add with an item name, or open the cart and use the screen to edit.';
      }
      if (affirmOnly) {
        return 'Say place order to pay, or say what to change, for example remove pizza from cart.';
      }
      if (declineOnly) {
        return 'Okay. Say open cart to see your items, or go home to keep browsing.';
      }
    }
    return null;
  }

  Future<String?> _handleCheckoutVoiceFlow(String text) async {
    final bridge = CustomerVoiceBridge.instance;
    final lower = text.toLowerCase();

    bool hasAny(List<String> words) => words.any(lower.contains);
    bool isPlaceOrder = hasAny([
      'place order',
      'place my order',
      'place the order',
      'checkout',
      'check out',
      'confirm order',
      'complete order',
      'order now',
    ]);
    bool wantsOnline = hasAny([
      'online payment',
      'online',
      'card',
      'pay online',
    ]);
    final wantsCod = lower.contains('cash on delivery') ||
        RegExp(r'\bcod\b').hasMatch(lower) ||
        RegExp(r'\bcash\b').hasMatch(lower);

    final awaitingPayment = bridge.voiceExpectingCheckoutPayment ||
        bridge.paymentMethodDialogVisible;

    if (!awaitingPayment) {
      if (!isPlaceOrder) {
        return null;
      }
      _restaurantBrowseActive = false;
      _restaurantBrowseOffset = 0;
      _restaurantBrowseCategoryId = null;
      _switchToTab(VoiceIntentRouter.tabCart);
      if (cartService.isEmpty) {
        bridge.voiceExpectingCheckoutPayment = false;
        return 'Your cart is empty. Add items before placing an order.';
      }
      bridge.voiceExpectingCheckoutPayment = true;
      bridge.showCartPaymentMethodDialog?.call();
      final summary =
          bridge.voiceFullCartSummary?.call() ?? 'Please review your cart.';
      return '$summary You are about to place your order. '
          'Would you like cash on delivery or online payment? '
          'Say your choice, or tap an option on the screen.';
    }

    _switchToTab(VoiceIntentRouter.tabCart);

    if (!wantsCod && !wantsOnline) {
      if (isPlaceOrder) {
        bridge.showCartPaymentMethodDialog?.call();
        final summary =
            bridge.voiceFullCartSummary?.call() ?? 'Please review your cart.';
        return '$summary Would you like cash on delivery or online payment?';
      }
      if (_isAffirmativeHearReviews(lower) && _isAffirmationOnlyUtterance(text)) {
        return 'Please say cash on delivery, or online payment, to choose how to pay.';
      }
      return 'Please say cash on delivery or online payment.';
    }
    final place = bridge.placeVoiceOrderWithPayment;
    if (place == null) {
      bridge.voiceExpectingCheckoutPayment = false;
      return 'Please open the cart first, then place order.';
    }
    final method = wantsOnline ? 'online' : 'cod';
    final err = await place(method);
    if (err != null) {
      return err;
    }
    _switchToTab(VoiceIntentRouter.tabOrders);
    return 'Order placed. I moved you to your orders page.';
  }

  /// Read latest reviews aloud when user is on a restaurant menu.
  String? _handleRestaurantReviewsVoiceFlow(String text) {
    final bridge = CustomerVoiceBridge.instance;
    if (bridge.confirmVoiceAddToCartFromMenu == null) {
      return null;
    }
    if (bridge.isVoiceReviewDialogOpen?.call() == true) {
      return null;
    }
    final lower = text.toLowerCase().trim();
    final mentionsReview = RegExp(r'\breviews?\b').hasMatch(lower) ||
        RegExp(r'\bratings?\b').hasMatch(lower) ||
        (lower.contains('review') &&
            (lower.contains('read') ||
                lower.contains('tell') ||
                lower.contains('hear') ||
                lower.contains('latest') ||
                lower.contains('show')));

    void clearReviewsOffer() {
      bridge.voiceAwaitingRestaurantReviewsYesNo = false;
    }

    final offeredReviews = bridge.voiceAwaitingRestaurantReviewsYesNo ||
        _assistantSpeechOffersRestaurantReviewsHearing(
          bridge.assistantSpeechLine.value,
        );

    if (mentionsReview) {
      clearReviewsOffer();
      return _restaurantReviewsTtsSummary();
    }
    if (offeredReviews && _isAffirmativeHearReviews(lower)) {
      clearReviewsOffer();
      return _restaurantReviewsTtsSummary();
    }
    if (offeredReviews && _isDeclineHearReviews(lower)) {
      clearReviewsOffer();
      return 'Okay.';
    }
    return null;
  }

  /// On restaurant menu: read all dishes or one section (appetizer, main, dessert, drinks).
  String? _handleRestaurantMenuListingVoice(String text) {
    final bridge = CustomerVoiceBridge.instance;
    final cb = bridge.speakableMenuItemsForVoice;
    if (cb == null || bridge.confirmVoiceAddToCartFromMenu == null) {
      return null;
    }
    if (bridge.isVoiceReviewDialogOpen?.call() == true) {
      return null;
    }
    final lower = text.toLowerCase().trim();
    if (RegExp(
      r'\b(add|remove|confirm\s+add|checkout|place\s+order)\b',
    ).hasMatch(lower)) {
      return null;
    }

    if (_utteranceWantsFullMenuItemsReadAloud(lower)) {
      return cb(categoryKey: null);
    }

    final cat = _voiceMenuDishCategoryKey(lower);
    final asksMenuCategory =
        RegExp(r'\bmenu\s+categor(y|ies)\b').hasMatch(lower);
    final asksCategoryWord = RegExp(r'\bcategory\b').hasMatch(lower);
    final asksSection =
        RegExp(r'\b(menu\s+)?sections?\b').hasMatch(lower) ||
        RegExp(r'\bwhich\s+section\b').hasMatch(lower);

    if (asksMenuCategory || asksCategoryWord || asksSection) {
      if (cat != null) {
        return cb(categoryKey: cat);
      }
      return 'Which section? Say appetizer, main course, dessert, or drinks.';
    }

    if (cat != null) {
      return cb(categoryKey: cat);
    }
    return null;
  }

  bool _utteranceWantsFullMenuItemsReadAloud(String lower) {
    if (RegExp(r'\bmenu\s+items?\b').hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'\b(list|read|tell|say|give|speak)(\s+me)?\s+(the\s+)?(all\s+)?(menu\s+items?|dishes?)\b',
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'\b(all\s+(the\s+)?dishes?|all\s+menu\s+items?)\b',
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'\b(whole|full|entire)\s+menu\b|\bcomplete\s+menu\b',
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r"\bwhat(?:'s|s| is)\s+on\s+the\s+menu\b|\beverything\s+on\s+the\s+menu\b",
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'\b(read|list|tell|say|give)\s+(me\s+)?(all\s+)?(sections?|courses?)\b',
    ).hasMatch(lower)) {
      return true;
    }
    final t = lower.trim();
    if (t == 'dishes' ||
        t == 'dish' ||
        RegExp(r'^the\s+dishes?\.?$').hasMatch(t)) {
      return true;
    }
    return false;
  }

  String? _voiceMenuDishCategoryKey(String lower) {
    if (lower.contains('appetizer') ||
        lower.contains('appetiser') ||
        RegExp(r'\bstarters?\b').hasMatch(lower) ||
        RegExp(r'\bfirst\s+course\b').hasMatch(lower)) {
      return MenuDishCategory.appetizer;
    }
    if (lower.contains('dessert') ||
        RegExp(r'\bdesserts\b').hasMatch(lower) ||
        RegExp(r'\bdesert\b').hasMatch(lower) ||
        RegExp(r'\b(sweets?|afters)\b').hasMatch(lower)) {
      return MenuDishCategory.dessert;
    }
    if (lower.contains('main course') ||
        lower.contains('main courses') ||
        RegExp(r'\b(entree|entrees)\b').hasMatch(lower) ||
        RegExp(r'\bmains?\b').hasMatch(lower)) {
      return MenuDishCategory.main;
    }
    if (lower.contains('drink') ||
        lower.contains('beverage') ||
        RegExp(r'\bdrinks\b').hasMatch(lower) ||
        RegExp(r'\b(juice|soda|soft\s+drink|coffee|tea)\b').hasMatch(lower)) {
      return MenuDishCategory.drink;
    }
    return null;
  }

  Future<void> _maybeSpeakRestaurantMenuIntro(String text) async {
    final b = CustomerVoiceBridge.instance;
    if (b.confirmVoiceAddToCartFromMenu == null) return;
    if (b.restaurantVoiceMenuIntroShown) return;
    if (_shouldSkipRestaurantIntroForUtterance(text)) return;
    final script = b.restaurantMenuIntroSpeech?.trim();
    if (script == null || script.isEmpty) return;
    await _tts.stop();
    await _tts.speak(script);
    _applyAssistantSpeechLine(script);
    b.restaurantVoiceMenuIntroShown = true;
    final scriptLower = script.toLowerCase();
    if (scriptLower.contains('hear the latest reviews') ||
        scriptLower.contains('like to hear the latest reviews')) {
      b.voiceAwaitingRestaurantReviewsYesNo = true;
    }
  }

  bool _shouldSkipRestaurantIntroForUtterance(String text) {
    final bridge = CustomerVoiceBridge.instance;
    final lower = text.toLowerCase().trim();
    if (_isRestaurantWhereAmIQuestion(lower)) return false;
    if (VoiceIntentRouter.classifyVoiceTabShortcut(
          text,
          onRestaurantMenu: bridge.confirmVoiceAddToCartFromMenu != null,
        ) !=
        VoiceTabShortcut.none) {
      return true;
    }
    if (_fragmentForFilterCategoryPick(lower) != null) return true;
    if (_utteranceLooksLikeFilterSheetCommand(text)) return true;
    if (_utteranceLooksLikeCheckoutCommand(lower)) return true;
    if (lower.contains('track') &&
        (lower.contains('order') || lower.contains('delivery'))) {
      return true;
    }
    if (_utteranceWantsFullMenuItemsReadAloud(lower)) {
      return true;
    }
    if (RegExp(r'\bmenu\s+categor(y|ies)\b').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'\bcategory\b').hasMatch(lower) &&
        _voiceMenuDishCategoryKey(lower) != null) {
      return true;
    }
    if (RegExp(r'\b(menu\s+)?sections?\b').hasMatch(lower) ||
        RegExp(r'\bwhich\s+section\b').hasMatch(lower)) {
      return true;
    }
    if (_voiceMenuDishCategoryKey(lower) != null) {
      return true;
    }
    return false;
  }

  bool _isRestaurantWhereAmIQuestion(String lower) {
    return lower.contains('where am i') ||
        lower.contains('what place is this') ||
        lower.contains('what place this') ||
        (lower.contains('what') && lower.contains('restaurant')) ||
        (lower.contains('which') && lower.contains('restaurant'));
  }

  bool _utteranceLooksLikeCheckoutCommand(String lower) {
    return lower.contains('place order') ||
        lower.contains('place my order') ||
        lower.contains('place the order') ||
        lower.contains('checkout') ||
        lower.contains('check out') ||
        lower.contains('complete order') ||
        lower.contains('confirm order');
  }

  bool _utteranceLooksLikeFilterSheetCommand(String text) {
    final lower = text.toLowerCase().trim();
    if (VoiceIntentRouter.explicitSearchRequested(text)) {
      return false;
    }
    return lower.contains('filter options') ||
        lower.contains('open filters') ||
        lower.contains('show filters') ||
        lower.contains('tell filters') ||
        lower.contains('apply filter') ||
        lower == 'filters' ||
        (RegExp(r'\bfilter\b').hasMatch(lower) &&
            !RegExp(r'\breviews?\b').hasMatch(lower) &&
            !RegExp(r'\bratings?\b').hasMatch(lower));
  }

  /// Last assistant line asked whether to hear restaurant reviews (menu context).
  /// Excludes post-delivery review dialog prompts so "yes" is not mis-routed.
  bool _assistantSpeechOffersRestaurantReviewsHearing(String lastSpeech) {
    final l = lastSpeech.toLowerCase();
    if (l.contains('submit or cancel')) {
      return false;
    }
    if (l.contains('add a comment')) {
      return false;
    }
    if (l.contains('how many stars')) {
      return false;
    }
    if (l.contains('hear the latest reviews')) {
      return true;
    }
    if (l.contains('like to hear the latest reviews')) {
      return true;
    }
    if (RegExp(r'\blisten\b').hasMatch(l) &&
        RegExp(r'\breviews?\b').hasMatch(l)) {
      return true;
    }
    if (l.contains('would you like') &&
        l.contains('hear') &&
        RegExp(r'\breviews?\b').hasMatch(l)) {
      return true;
    }
    return false;
  }

  bool _isAffirmativeHearReviews(String lower) {
    const words = [
      'yes',
      'yeah',
      'yep',
      'sure',
      'okay',
      'ok',
      'please',
      'haan',
    ];
    for (final w in words) {
      if (RegExp(r'\b' + RegExp.escape(w) + r'\b').hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  bool _isDeclineHearReviews(String lower) {
    const words = [
      'no',
      'nope',
      'nah',
      'not now',
      "don't",
      'do not',
      'skip',
      'later',
      'nahi',
    ];
    for (final w in words) {
      if (w.contains(' ')) {
        if (lower.contains(w)) {
          return true;
        }
      } else if (RegExp(r'\b' + RegExp.escape(w) + r'\b').hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  String _restaurantReviewsTtsSummary() {
    final summary =
        CustomerVoiceBridge.instance.restaurantVoiceReviewsSummary?.trim();
    if (summary == null || summary.isEmpty) {
      return 'There are no reviews loaded for this restaurant yet.';
    }
    return summary;
  }

  /// "choose filter X" / "filter X" (handled here so the sheet does not block TTS).
  Future<String?> _handleFilterCategoryPick(String text) async {
    final lower = text.toLowerCase().trim();
    final fragment = _fragmentForFilterCategoryPick(lower);
    if (fragment == null) {
      return null;
    }

    _switchToTab(VoiceIntentRouter.tabHome);
    final bridge = CustomerVoiceBridge.instance;

    if (fragment == 'all' ||
        fragment == 'any' ||
        fragment == 'everything' ||
        fragment == 'clear') {
      bridge.applyCategoryId?.call(null);
      return 'Showing all categories. Open now stays on — only open restaurants are listed.';
    }

    final id = _resolveCategoryIdFromFragment(fragment);
    if (id == null) {
      return 'I did not recognize that category. Say filter options to hear all category names.';
    }
    bridge.applyCategoryId?.call(id);
    String? label;
    for (final c in kSdLibRestaurantCategories) {
      if (c.id == id) {
        label = c.label;
        break;
      }
    }
    return await ttsLineForExploreCategoryFilter(
      categoryId: id,
      categoryLabel: label ?? id,
    );
  }

  /// Returns a category phrase, or null if this utterance should open/list filters instead.
  String? _fragmentForFilterCategoryPick(String lower) {
    var m = RegExp(r'^choose\s+(?:the\s+)?filter\s+(.+)$').firstMatch(lower);
    if (m != null) {
      return m.group(1)?.trim();
    }
    m = RegExp(r'^set\s+filter\s+to\s+(.+)$').firstMatch(lower);
    if (m != null) {
      return m.group(1)?.trim();
    }
    m = RegExp(r'^pick\s+(?:the\s+)?filter\s+(.+)$').firstMatch(lower);
    if (m != null) {
      return m.group(1)?.trim();
    }
    if (lower.startsWith('filter ')) {
      final rest = lower.substring('filter '.length).trim();
      if (rest.length < 2) {
        return null;
      }
      if (rest == 'options' || rest.startsWith('options')) {
        return null;
      }
      if (rest == 'sheet' || rest.startsWith('sheet')) {
        return null;
      }
      if (rest == 'bar' || rest == 'menu' || rest == 'by') {
        return null;
      }
      if (rest.startsWith('by ')) {
        return null;
      }
      if (rest == 'open now' || rest == 'the options') {
        return null;
      }
      return rest;
    }
    return null;
  }

  String? _resolveCategoryIdFromFragment(String fragment) {
    final f = fragment.toLowerCase().trim();
    if (f.isEmpty) {
      return null;
    }
    for (final c in kSdLibRestaurantCategories) {
      final label = c.label.toLowerCase().trim();
      if (label.isNotEmpty && (f.contains(label) || label.contains(f))) {
        return c.id;
      }
    }
    return _detectCategoryId(f);
  }

  Future<String?> _handleFilterVoiceFlow(String text) async {
    final lower = text.toLowerCase().trim();
    bool hasAny(List<String> parts) => parts.any(lower.contains);
    final hasExplicitHomeSearch = VoiceIntentRouter.explicitSearchRequested(text);

    final showMore = _filterBrowseActive &&
        hasAny([
          'show more',
          'tell more',
          'give more',
          'more filters',
          'next filters',
        ]);

    final newFilterSession = !showMore &&
        (lower == 'filters' ||
            hasAny([
              'open filters',
              'show filters',
              'tell filters',
              'filter options',
              'apply filter',
              'use filter',
              'filter by',
              'set filter',
            ]) ||
            (RegExp(r'\bfilter\b').hasMatch(lower) && !hasExplicitHomeSearch));

    if (!newFilterSession && !showMore) {
      return null;
    }

    final bridge = CustomerVoiceBridge.instance;
    final categoryLabels = <String>[
      'All',
      ...kSdLibRestaurantCategories.map((c) => c.label),
    ];

    if (newFilterSession) {
      final opener = bridge.openExploreFilters;
      if (opener != null) {
        unawaited(opener());
      }
      _filterBrowseActive = true;
      _filterBrowseOffset = 0;
      final cat = _detectCategoryId(lower);
      if (cat != null) {
        bridge.applyCategoryId?.call(cat);
        String? label;
        for (final c in kSdLibRestaurantCategories) {
          if (c.id == cat) {
            label = c.label;
            break;
          }
        }
        final listLine = await ttsLineForExploreCategoryFilter(
          categoryId: cat,
          categoryLabel: label ?? cat,
        );
        return 'Opened the filter sheet. $listLine';
      }
      final allCats = categoryLabels.join(', ');
      return 'Opened the filter sheet. '
          'Here are the categories: $allCats. '
          'Open now is on, so only restaurants open right now are shown. '
          'Say choose filter followed by a name to pick one, or tap the sheet.';
    }

    final start = _filterBrowseOffset;
    if (start >= categoryLabels.length) {
      _filterBrowseOffset = 0;
      return 'Say open filters to hear the category list from the start.';
    }
    final end = (start + 5).clamp(0, categoryLabels.length);
    final chunk = categoryLabels.sublist(start, end);
    _filterBrowseOffset = end;
    final hasMore = _filterBrowseOffset < categoryLabels.length;
    final suffix = hasMore ? ' Say show more for additional names.' : '';
    return 'More categories: ${chunk.join(', ')}.$suffix';
  }

  Future<String?> _handleRestaurantBrowseFlow(String text) async {
    final lower = text.toLowerCase().trim();
    bool hasAny(List<String> parts) => parts.any(lower.contains);
    final wantsList = hasAny([
      'restaurant names',
      'tell me the names of',
      'show restaurants',
      'list restaurants',
      'which restaurants',
      'restaurant list',
    ]);
    final wantsMore = hasAny([
      'tell more',
      'give more',
      'more restaurant',
      'next restaurant',
      'more names',
    ]);

    final categoryId = _detectCategoryId(lower);
    final openMatch = RegExp(
      r'(?:open|go to)\s+([a-z0-9&\-\s]{2,})',
    ).firstMatch(lower);
    final openName = openMatch?.group(1)?.trim();

    if (!_restaurantBrowseActive && !wantsList) {
      return null;
    }

    if (!_restaurantBrowseActive && wantsList) {
      _restaurantBrowseActive = true;
      _restaurantBrowseOffset = 0;
      _restaurantBrowseCategoryId = null;
      final page = await fetchRestaurantNamesForVoice(
        categoryId: null,
        offset: 0,
        limit: 3,
        openNowOnly: true,
      );
      if (page == null || page.names.isEmpty) {
        _restaurantBrowseActive = false;
        return 'With open now on, I could not find open restaurants near you right now. '
            'Try turning off open now on the filter sheet, or check your city in Profile.';
      }
      _restaurantBrowseOffset = page.names.length;
      final names = formatExploreNamesForTts(page.names);
      final tail = page.hasMore ? ' More are on your screen.' : '';
      return 'Open now is on. Here are some restaurant names: $names.$tail '
          'Would you like a specific cuisine like fast food or coffee?';
    }

    if (openName != null && openName.isNotEmpty) {
      final opener = CustomerVoiceBridge.instance.openRestaurantByName;
      if (opener == null) {
        return 'I cannot open restaurants from this screen right now.';
      }
      final opened = await opener(openName);
      if (opened) {
        _restaurantBrowseActive = false;
        _restaurantBrowseOffset = 0;
        _restaurantBrowseCategoryId = null;
        return 'Opened $openName.';
      }
      return 'I could not find $openName. Say tell more for more names.';
    }

    if (categoryId != null) {
      _restaurantBrowseCategoryId = categoryId;
      _restaurantBrowseOffset = 0;
      CustomerVoiceBridge.instance.applyCategoryId?.call(categoryId);
      final page = await fetchRestaurantNamesForVoice(
        categoryId: categoryId,
        offset: 0,
        limit: 3,
        openNowOnly: true,
      );
      if (page == null || page.names.isEmpty) {
        return 'With open now on, I did not find open restaurants in that category near you. '
            'Try another cuisine or turn off open now on the filter sheet.';
      }
      _restaurantBrowseOffset = page.names.length;
      final names = formatExploreNamesForTts(page.names);
      final tail = page.hasMore ? ' More are on your screen.' : '';
      return 'Open now is on. In that category, open restaurants you can try: $names.$tail '
          'Say tell more to hear more names, or say open followed by a restaurant name.';
    }

    if (wantsMore) {
      final page = await fetchRestaurantNamesForVoice(
        categoryId: _restaurantBrowseCategoryId,
        offset: _restaurantBrowseOffset,
        limit: 5,
        openNowOnly: true,
      );
      if (page == null || page.names.isEmpty) {
        return 'No more open restaurant names in this list with open now on. '
            'Say a cuisine or say open with a restaurant name.';
      }
      _restaurantBrowseOffset += page.names.length;
      final names = formatExploreNamesForTts(page.names);
      final tail = page.hasMore ? ' More on your screen.' : '';
      return 'Open now is on. More restaurant names: $names.$tail';
    }

    return 'Say tell more for more names, say a cuisine like fast food or coffee, '
        'or say open followed by the restaurant name.';
  }

  String? _detectCategoryId(String lower) {
    for (final c in kSdLibRestaurantCategories) {
      final label = c.label.toLowerCase().trim();
      if (label.isNotEmpty && lower.contains(label)) {
        return c.id;
      }
    }
    if (lower.contains('fast food') || lower.contains('fastfood')) {
      return 'fast_food';
    }
    if (RegExp(r'caf[ée]\s*(?:&|and)\s*coffee').hasMatch(lower) ||
        lower.contains('coffee') ||
        lower.contains('cafe') ||
        lower.contains('café')) {
      return 'cafe';
    }
    return null;
  }

  void dispose() {
    _stt.cancelListening();
    _tts.stop();
    _reviewStage = _VoiceReviewStage.idle;
    final bridge = CustomerVoiceBridge.instance;
    bridge.voiceExpectingCheckoutPayment = false;
    bridge.voiceAwaitingBrowseCuisineHint = false;
    bridge.voiceAwaitingCartAddMorePrompt = false;
    bridge.voiceAwaitingCartOrderOrChangesPrompt = false;
    bridge.voiceAwaitingEmptyCartBrowsePrompt = false;
    _restaurantBrowseActive = false;
    _restaurantBrowseOffset = 0;
    _restaurantBrowseCategoryId = null;
    _filterBrowseActive = false;
    _filterBrowseOffset = 0;
    bridge.voiceListening.value = false;
  }
}

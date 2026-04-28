import 'package:flutter/material.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/services/text_to_speech_service.dart';
import 'package:speak_dine/view/common/settings_view.dart';
import 'package:speak_dine/voice/cart_natural_language.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/voice/explore_restaurant_voice.dart';
import 'package:speak_dine/voice/voice_intent_models.dart';

/// Obvious tab / tracking phrases handled before restaurant-name resolution or cloud intent.
enum VoiceTabShortcut {
  none,
  home,
  cart,
  cartItems,
  payments,
  profile,
  orders,
  trackOrder,
}

/// Executes navigation + TTS from a [VoiceIntentResult].
class VoiceIntentRouter {
  /// When [speakAloud] is false, navigation still runs but the router does not call TTS
  /// (e.g. SpeakTime conversational model already produced the spoken script).
  VoiceIntentRouter({
    required this.switchToTab,
    required TextToSpeechService tts,
    bool initialSpeakAloud = true,
  }) : _tts = tts,
       speakAloud = initialSpeakAloud;

  final void Function(int index) switchToTab;
  final TextToSpeechService _tts;

  /// When false, [handle] still navigates but skips TTS (conversational model spoke already).
  bool speakAloud;

  static const int tabHome = 0;
  static const int tabCart = 1;
  static const int tabOrders = 2;
  static const int tabPayments = 3;
  static const int tabProfile = 4;

  String _lastSpoken = '';

  /// Phrases like "go to homepage" or "track my order" (no side effects).
  static VoiceTabShortcut classifyVoiceTabShortcut(
    String? raw, {
    /// When true, "items" alone is left to restaurant menu voice (not cart items).
    bool onRestaurantMenu = false,
  }) {
    final text = raw?.toLowerCase().trim() ?? '';
    if (text.isEmpty) return VoiceTabShortcut.none;
    bool hasAny(List<String> parts) => parts.any(text.contains);

    if (hasAny([
          'track my order',
          'track the order',
          'track this order',
          'track order',
          'track my delivery',
          'track delivery',
          'where is my order',
          'where is the order',
          'where my order',
          'order status',
          'delivery status',
          'order tracking',
        ]) ||
        (text.contains('track') && text.contains('order')) ||
        (text.contains('track') && text.contains('delivery'))) {
      return VoiceTabShortcut.trackOrder;
    }

    if (text == 'cart' ||
        hasAny([
          'open cart',
          'show cart',
          'my cart',
          'shopping cart',
          'go to cart',
          'cart tab',
        ])) {
      return VoiceTabShortcut.cart;
    }
    if ((!onRestaurantMenu && text == 'items') ||
        hasAny(['my items', 'cart items', 'order items'])) {
      return VoiceTabShortcut.cartItems;
    }
    if (hasAny([
      'open transactions',
      'transactions page',
      'payment page',
      'payments page',
    ])) {
      return VoiceTabShortcut.payments;
    }
    if (text == 'profile' ||
        hasAny([
          'open profile',
          'profile page',
          'my profile',
          'account page',
        ])) {
      return VoiceTabShortcut.profile;
    }
    if (text == 'orders' ||
        (!text.contains('track') &&
            (text == 'order' ||
                hasAny([
                  'open order page',
                  'open orders',
                  'orders page',
                  'my orders',
                  'order history',
                ])))) {
      return VoiceTabShortcut.orders;
    }

    if (text == 'home' ||
        text == 'homepage' ||
        text == 'restaurants' ||
        text == 'restaurant' ||
        RegExp(r'\bhome\s*page\b').hasMatch(text) ||
        hasAny([
          'open home',
          'go home',
          'go to home',
          'go to homepage',
          'go to home page',
          'go to the homepage',
          'open homepage',
          'restaurants page',
          'browse restaurants',
          'take me home',
          'main screen',
        ]) ||
        (text.contains('go to') &&
            RegExp(r'\bhome(page)?\b|\bhome\s+page\b').hasMatch(text))) {
      return VoiceTabShortcut.home;
    }
    return VoiceTabShortcut.none;
  }

  static int? tabIndexFromKeyword(String? raw) {
    final n = raw?.toLowerCase().trim() ?? '';
    switch (n) {
      case 'home':
      case 'restaurants':
      case 'browse':
        return tabHome;
      case 'cart':
      case 'basket':
        return tabCart;
      case 'orders':
      case 'order':
      case 'my orders':
        return tabOrders;
      case 'payments':
      case 'payment':
      case 'transactions':
        return tabPayments;
      case 'profile':
      case 'account':
        return tabProfile;
      default:
        return null;
    }
  }

  Future<String> _speak(String s) async {
    final t = s.trim();
    _lastSpoken = t;
    if (speakAloud) {
      await _tts.speak(t);
    }
    return t;
  }

  void _notifyCart() {
    CustomerVoiceBridge.instance.notifyCartChanged?.call();
  }

  void _clearVoiceFlow(CustomerVoiceBridge b) {
    b.clearPendingVoiceCartItem();
    b.voiceAwaitingCustomizeYesNo = false;
    b.voiceAwaitingCustomizationText = false;
    b.pendingVoiceCustomizationItem = null;
    b.voiceAwaitingRemoveCustomizationItem = false;
  }

  /// Tab navigation only; returns the line the assistant should speak (caller may TTS).
  Future<String> voiceTabShortcutLine(VoiceTabShortcut k) async {
    final bridge = CustomerVoiceBridge.instance;
    switch (k) {
      case VoiceTabShortcut.none:
        return '';
      case VoiceTabShortcut.home:
        switchToTab(tabHome);
        bridge.resetRestaurantStack?.call();
        return 'Home page.';
      case VoiceTabShortcut.cart:
      case VoiceTabShortcut.cartItems:
        switchToTab(tabCart);
        return 'Cart.';
      case VoiceTabShortcut.payments:
        switchToTab(tabPayments);
        return 'Payments.';
      case VoiceTabShortcut.profile:
        switchToTab(tabProfile);
        return 'Profile.';
      case VoiceTabShortcut.orders:
        switchToTab(tabOrders);
        return 'Orders.';
      case VoiceTabShortcut.trackOrder:
        final opener = bridge.openActiveOrderTracking;
        if (opener == null) {
          switchToTab(tabOrders);
          return 'Orders.';
        }
        final line = await opener();
        return line ??
            'You have no active order to track right now. Open My Orders to see your history.';
    }
  }

  Future<String> _handleVoiceTabShortcut(VoiceTabShortcut k) async {
    final line = await voiceTabShortcutLine(k);
    return _speak(line);
  }

  String _cartFullSummaryForTts() {
    final bridgeSummary = CustomerVoiceBridge.instance.voiceFullCartSummary
        ?.call();
    if (bridgeSummary != null && bridgeSummary.trim().isNotEmpty) {
      return bridgeSummary.trim();
    }
    final parts = <String>[];
    for (final e in cartService.cart.entries) {
      for (final item in e.value) {
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          continue;
        }
        final q = item['quantity'];
        var qty = 1;
        if (q is num) {
          qty = q.toInt().clamp(1, 999);
        }
        parts.add(qty > 1 ? '$qty $name' : '1 $name');
      }
    }
    if (parts.isEmpty) {
      return '';
    }
    return parts.join(', ');
  }

  String _cartItemNamesForTts() {
    final names = cartService.cartItemNames();
    if (names.isEmpty) {
      return 'Your cart is empty.';
    }
    return names.join(', ');
  }

  /// True only when the user starts with an explicit home-explore command (after
  /// optional "please" / "can you") and there is non-empty query text. Avoids
  /// substring hits like "research" or "searching later" and dish-only phrases.
  static bool explicitSearchRequested(String? utterance) {
    if (utterance == null) return false;
    final trimmed = utterance.trim();
    if (trimmed.isEmpty) return false;
    var s = trimmed;
    final leadIn = RegExp(
      r'^(?:please|can\s+you|could\s+you|hey|ok|okay|yes)\s+',
      caseSensitive: false,
    );
    for (var i = 0; i < 4; i++) {
      final m = leadIn.firstMatch(s);
      if (m == null) {
        break;
      }
      s = s.substring(m.end).trimLeft();
    }
    final lower = s.toLowerCase();
    final explicitCommand = RegExp(
      r'^(?:search(?:\s+for)?|look\s+for|lookfor|find|show\s+me)\b',
      caseSensitive: false,
    );
    if (!explicitCommand.hasMatch(lower)) {
      return false;
    }
    final q = normalizeExploreSearchQuery(trimmed);
    return q != null && q.isNotEmpty;
  }

  /// Voice often sends the whole phrase ("search jbs"). Strip command words so the
  /// bar shows only the target (e.g. `jbs`). Removes apostrophes so STT `jb's` matches `JBs`.
  static String? normalizeExploreSearchQuery(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final leadIn = RegExp(
      r'^(?:please|can\s+you|could\s+you|hey|ok|okay|yes)\s+',
      caseSensitive: false,
    );
    for (var i = 0; i < 4; i++) {
      final m = leadIn.firstMatch(s);
      if (m == null) {
        break;
      }
      s = s.substring(m.end).trimLeft();
    }
    final prefixRes = <RegExp>[
      RegExp(r'^look\s+for\s+', caseSensitive: false),
      RegExp(r'^lookfor\s+', caseSensitive: false),
      RegExp(r'^search(\s+for)?\s+', caseSensitive: false),
      RegExp(r'^find\s+', caseSensitive: false),
      RegExp(r'^show\s+me\s+', caseSensitive: false),
    ];
    for (var i = 0; i < 4; i++) {
      var hit = false;
      for (final re in prefixRes) {
        final m = re.firstMatch(s);
        if (m != null) {
          s = s.substring(m.end).trim();
          hit = true;
          break;
        }
      }
      if (!hit) break;
    }
    s = s.replaceAll("'", '').replaceAll('\u2019', '').trim();
    if (s.isEmpty) return null;
    return s;
  }

  Future<String> _pushSettings(CustomerVoiceBridge b) async {
    final ctx = b.shellContext;
    if (ctx != null && ctx.mounted) {
      await Navigator.of(ctx).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SettingsView()),
      );
    }
    return _speak('Opening settings.');
  }

  Future<String> handle(
    VoiceIntentResult r, {
    String? userUtterance,
  }) async {
    await _tts.stop();
    final bridge = CustomerVoiceBridge.instance;
    final allowSearch = explicitSearchRequested(userUtterance);

    switch (r.kind) {
      case VoiceIntentKind.nonFood:
        return _speak(
          'That does not sound like food or ordering. '
          'Try naming a dish, a restaurant, or say open cart.',
        );

      case VoiceIntentKind.unknown:
        final utter = (userUtterance ?? '').trim();
        final onRestaurantMenu = bridge.confirmVoiceAddToCartFromMenu != null;
        var q = (r.extractedQuery ?? r.itemName ?? '').trim();
        if (q.isEmpty && allowSearch && userUtterance != null) {
          q = userUtterance.trim();
        }
        var navKind = utter.isNotEmpty
            ? classifyVoiceTabShortcut(utter, onRestaurantMenu: onRestaurantMenu)
            : VoiceTabShortcut.none;
        if (navKind == VoiceTabShortcut.none && q.isNotEmpty) {
          navKind = classifyVoiceTabShortcut(q, onRestaurantMenu: onRestaurantMenu);
        }
        if (navKind != VoiceTabShortcut.none) {
          return _handleVoiceTabShortcut(navKind);
        }
        if (allowSearch && !onRestaurantMenu) {
          switchToTab(tabHome);
        }
        final searchBar =
            (allowSearch && !onRestaurantMenu) ? normalizeExploreSearchQuery(q) : null;
        if (searchBar != null && allowSearch && !onRestaurantMenu) {
          bridge.applySearchQuery?.call(searchBar);
        }
        final qLower = q.toLowerCase();
        final looksLikeRestaurantLookup =
            qLower.contains('restaurant') ||
            qLower.contains('resturant') ||
            qLower.contains('resterant');
        if (looksLikeRestaurantLookup) {
          return _speak(
            'Restaurant not found choose another restaurant using options in filters.',
          );
        }
        if (r.isFoodOrOrderingRelated) {
          if (onRestaurantMenu) {
            return _speak(
              'I did not catch that menu action. You can say menu items, a dish name, confirm add, or go back.',
            );
          }
          return _speak(
            allowSearch
                ? 'Searching for that. Say add to cart with a dish name, open cart, or go home.'
                : 'Say search with what you want to find, use filters to narrow cuisine, or open a restaurant.',
          );
        }
        return _speak(
          'Sorry, I did not understand. Try again or use the screen.',
        );

      case VoiceIntentKind.cancelAction:
        await _tts.stop();
        _clearVoiceFlow(bridge);
        return _speak('Okay, cancelled.');

      case VoiceIntentKind.addToCartRequest:
        final item = (r.itemName ?? r.extractedQuery ?? '').trim();
        if (item.isEmpty) {
          return _speak(
            'Say what to add, for example: add burger to cart. '
            'Then open that restaurant and say confirm add.',
          );
        }
        bridge.pendingVoiceCartItem = item;
        final onRestaurantMenu = bridge.confirmVoiceAddToCartFromMenu != null;
        if (onRestaurantMenu) {
          final confirm = bridge.confirmVoiceAddToCartFromMenu;
          final err = await confirm!();
          if (err == null) {
            _notifyCart();
            bridge.pendingVoiceCustomizationItem = item;
            bridge.voiceAwaitingCustomizeYesNo = true;
            bridge.voiceAwaitingCustomizationText = false;
            bridge.voiceAwaitingRestaurantReviewsYesNo = false;
            bridge.voiceAwaitingBrowseCuisineHint = false;
            bridge.voiceAwaitingCartAddMorePrompt = false;
            bridge.voiceAwaitingCartOrderOrChangesPrompt = false;
            bridge.voiceAwaitingEmptyCartBrowsePrompt = false;
            return _speak(
              '$item has been added to your cart. Would you like to customise this item?',
            );
          }
          return _speak(err);
        }
        switchToTab(tabHome);
        if (allowSearch) {
          final sq = normalizeExploreSearchQuery(item) ?? item;
          bridge.applySearchQuery?.call(sq);
          return _speak(
            'Looking for $sq. Open the restaurant menu, then say confirm add.',
          );
        }
        bridge.pendingVoiceCartItem = item;
        return _speak(
          'Say search for $item to look it up on the home screen, '
          'or open a restaurant, then say confirm add.',
        );

      case VoiceIntentKind.selectMenuItem:
        final rest = (r.restaurantName ?? '').trim();
        if (rest.isNotEmpty) {
          final mistakenNav = classifyVoiceTabShortcut(rest);
          if (mistakenNav != VoiceTabShortcut.none) {
            return _handleVoiceTabShortcut(mistakenNav);
          }
        }
        switchToTab(tabHome);
        if (rest.isNotEmpty) {
          final opener = bridge.openRestaurantByName;
          if (opener != null) {
            final opened = await opener(rest);
            if (opened) {
              final dish = (r.itemName ?? r.extractedQuery ?? '').trim();
              if (dish.isNotEmpty) {
                bridge.pendingVoiceCartItem = dish;
              }
              return _speak(
                'Opened $rest. Say confirm add when you see your dish.',
              );
            }
            if (allowSearch) {
              final sq = normalizeExploreSearchQuery(rest) ?? rest;
              bridge.applySearchQuery?.call(sq);
            }
            return _speak(
              'Restaurant not found choose another restaurant using options in filters.',
            );
          }
        }
        if (r.categoryId != null) {
          switchToTab(tabHome);
          bridge.applyCategoryId?.call(r.categoryId);
          String? label;
          for (final c in kSdLibRestaurantCategories) {
            if (c.id == r.categoryId) {
              label = c.label;
              break;
            }
          }
          final line = await ttsLineForExploreCategoryFilter(
            categoryId: r.categoryId!,
            categoryLabel: label ?? r.categoryId!,
          );
          return _speak(line);
        }
        final dish = (r.itemName ?? r.extractedQuery ?? '').trim();
        if (dish.isNotEmpty) {
          bridge.pendingVoiceCartItem = dish;
          if (bridge.confirmVoiceAddToCartFromMenu != null) {
            return _speak(
              'Okay, $dish on this menu. Say confirm add to add it.',
            );
          }
          switchToTab(tabHome);
          if (allowSearch) {
            final sq = normalizeExploreSearchQuery(dish) ?? dish;
            bridge.applySearchQuery?.call(sq);
            return _speak(
              'Searching for $sq. Open a menu, then say confirm add.',
            );
          }
          bridge.pendingVoiceCartItem = dish;
          return _speak(
            'Say search for $dish to find it, or open a restaurant menu first.',
          );
        }
        return _speak('Say a restaurant or dish to select.');

      case VoiceIntentKind.confirmAddToCart:
        final confirm = bridge.confirmVoiceAddToCartFromMenu;
        if (confirm == null) {
          switchToTab(tabHome);
          return _speak(
            'Open a restaurant menu first. If you have not said what to add, say add to cart with the dish name.',
          );
        }
        final err = await confirm();
        if (err != null) {
          return _speak(err);
        }
        _notifyCart();
        final label = (bridge.pendingVoiceCartItem ?? '').trim();
        bridge.pendingVoiceCustomizationItem = label.isNotEmpty ? label : null;
        bridge.voiceAwaitingCustomizeYesNo = true;
        bridge.voiceAwaitingCustomizationText = false;
        bridge.voiceAwaitingRestaurantReviewsYesNo = false;
        bridge.voiceAwaitingBrowseCuisineHint = false;
        bridge.voiceAwaitingCartAddMorePrompt = false;
        bridge.voiceAwaitingCartOrderOrChangesPrompt = false;
        bridge.voiceAwaitingEmptyCartBrowsePrompt = false;
        final line = label.isNotEmpty
            ? '$label has been added to your cart. Would you like to customise this item?'
            : 'Your item has been added to your cart. Would you like to customise this item?';
        return _speak(line);

      case VoiceIntentKind.addToCartIntent:
        if ((bridge.pendingVoiceCartItem ?? '').trim().isNotEmpty) {
          final confirm = bridge.confirmVoiceAddToCartFromMenu;
          if (confirm != null) {
            final err = await confirm();
            if (err == null) {
              _notifyCart();
              final label = (bridge.pendingVoiceCartItem ?? '').trim();
              bridge.pendingVoiceCustomizationItem = label.isNotEmpty
                  ? label
                  : null;
              bridge.voiceAwaitingCustomizeYesNo = true;
              bridge.voiceAwaitingCustomizationText = false;
              bridge.voiceAwaitingRestaurantReviewsYesNo = false;
              bridge.voiceAwaitingBrowseCuisineHint = false;
              bridge.voiceAwaitingCartAddMorePrompt = false;
              bridge.voiceAwaitingCartOrderOrChangesPrompt = false;
              bridge.voiceAwaitingEmptyCartBrowsePrompt = false;
              final line = label.isNotEmpty
                  ? '$label has been added to your cart. Would you like to customise this item?'
                  : 'Your item has been added to your cart. Would you like to customise this item?';
              return _speak(line);
            }
            return _speak(err);
          }
        }
        return _speak(
          'Say what to add, for example add burger to cart. '
          'Or open a menu first, then say confirm add.',
        );

      case VoiceIntentKind.ambiguousOrderIntent:
        return _speak(
          'Do you want to add food to the cart, or go to checkout? '
          'Say add to cart with the item name, or say open cart.',
        );

      case VoiceIntentKind.openCartIntent:
        switchToTab(tabCart);
        if (cartService.isEmpty) {
          return _speak(
            'Your cart is empty. Would you like to browse restaurants or search for a dish?',
          );
        }
        final summary = _cartFullSummaryForTts();
        return _speak(
          'Here are the items in your cart: $summary. '
          'Would you like to place your order or make changes?',
        );

      case VoiceIntentKind.cartNaturalLanguageEdit:
        switchToTab(tabCart);
        final phrase = (r.extractedQuery ?? r.itemName ?? '').trim();
        if (phrase.isEmpty) {
          return _speak(
            'Say what to change, for example: add one more coffee and remove sandwich.',
          );
        }
        final line = CartNaturalLanguage.applyFromUtterance(phrase);
        _notifyCart();
        return _speak(line);

      case VoiceIntentKind.customizeCartItem:
        final item = (r.itemName ?? r.extractedQuery ?? '').trim();
        if (item.isEmpty) {
          return _speak(
            'Please say which cart item to customise, for example customise burger.',
          );
        }
        if (!cartService.hasMatchingItem(item)) {
          return _speak(
            'I could not find $item in your cart. Please say an item that is already in your cart.',
          );
        }
        bridge.pendingVoiceCustomizationItem = item;
        bridge.voiceAwaitingCustomizeYesNo = false;
        bridge.voiceAwaitingCustomizationText = true;
        bridge.voiceAwaitingRestaurantReviewsYesNo = false;
        final existing = cartService.firstNoteForMatchingItem(item);
        if (existing != null && existing.isNotEmpty) {
          return _speak(
            'Current customisation for $item is: $existing. '
            'Tell me what to write in the customisation note.',
          );
        }
        return _speak('What customisation would you like for $item?');

      case VoiceIntentKind.provideCustomizationNote:
        var item = (bridge.pendingVoiceCustomizationItem ?? '').trim();
        var note = (r.extractedQuery ?? '').trim();
        if (item.isEmpty) {
          final matched = cartService.firstMatchingItemNameInText(note);
          if (matched != null && matched.isNotEmpty) {
            item = matched;
            note = note.replaceFirst(RegExp(RegExp.escape(matched), caseSensitive: false), '').trim();
            note = note
                .replaceFirst(RegExp(r'^(for|of)\s+', caseSensitive: false), '')
                .trim();
          }
        }
        if (item.isEmpty) {
          return _speak(
            'Please say customise followed by the item name first, for example customise burger.',
          );
        }
        if (note.isEmpty) {
          bridge.voiceAwaitingCustomizationText = true;
          bridge.pendingVoiceCustomizationItem = item;
          return _speak('Please tell me the customisation note for $item.');
        }
        final updated = cartService.setNoteForMatchingItems(item, note);
        if (updated == 0) {
          return _speak(
            'I could not find $item in your cart. Please open cart and try again.',
          );
        }
        _notifyCart();
        bridge.voiceAwaitingCustomizationText = false;
        bridge.voiceAwaitingCustomizeYesNo = false;
        return _speak('Customisation saved for $item. Would you like anything else?');

      case VoiceIntentKind.removeCartItemCustomization:
        final item = (r.itemName ?? '').trim();
        if (item.isEmpty) {
          bridge.voiceAwaitingRemoveCustomizationItem = true;
          final names = _cartItemNamesForTts();
          return _speak(
            'For which cart item should I remove customisation? '
            'Your cart items are: $names',
          );
        }
        final updated = cartService.clearNoteForMatchingItems(item);
        if (updated == 0) {
          return _speak(
            'I could not find $item in your cart. Please try another item name.',
          );
        }
        _notifyCart();
        bridge.voiceAwaitingRemoveCustomizationItem = false;
        return _speak('Customisation removed for $item. Would you like anything else?');

      case VoiceIntentKind.listCartItemsIntent:
        switchToTab(tabCart);
        final names = _cartItemNamesForTts();
        if (names == 'Your cart is empty.') {
          return _speak('Your cart is empty.');
        }
        return _speak('Here are the items in your cart: $names');

      case VoiceIntentKind.initiateCheckout:
        switchToTab(tabCart);
        if (cartService.isEmpty) {
          bridge.voiceExpectingCheckoutPayment = false;
          return _speak(
            'Your cart is empty. Add items before placing an order.',
          );
        }
        bridge.voiceExpectingCheckoutPayment = true;
        bridge.showCartPaymentMethodDialog?.call();
        return _speak(
          "Opening checkout. Would you like cash on delivery or online payment? "
          'Say cash on delivery, or online payment, or tap your choice on the screen.',
        );

      case VoiceIntentKind.confirmOrderUIOnly:
        switchToTab(tabCart);
        return _speak(
          'Please confirm your order on the screen to complete the payment.',
        );

      case VoiceIntentKind.cancelCheckout:
        _clearVoiceFlow(bridge);
        bridge.popRestaurantRoute?.call();
        return _speak(
          'Okay. Checkout cancelled. You can keep editing your cart.',
        );

      case VoiceIntentKind.openSettings:
        return _pushSettings(bridge);

      case VoiceIntentKind.toggleSetting:
        await _pushSettings(bridge);
        return _speak(
          'Use the switches on the settings page. Say the setting name if we add shortcuts later.',
        );

      case VoiceIntentKind.updateSettingValue:
        final key = (r.settingKey ?? '').toLowerCase().trim();
        final val = (r.settingValue ?? r.extractedQuery ?? '').trim();
        if (key == 'username' || key == 'name' || key == 'displayname') {
          if (val.isEmpty) {
            return _speak('Say your new username after update my name.');
          }
          final update = bridge.updateCustomerDisplayName;
          if (update == null) {
            return _speak('Open Profile to change your name.');
          }
          final err = await update(val);
          if (err != null) {
            return _speak(err);
          }
          switchToTab(tabProfile);
          return _speak('Your name is updated.');
        }
        await _pushSettings(bridge);
        if (val.isNotEmpty) {
          return _speak('Open the setting you need and enter $val on screen.');
        }
        return _speak('Choose the value on the settings screen.');

      case VoiceIntentKind.goHome:
        return _handleVoiceTabShortcut(VoiceTabShortcut.home);

      case VoiceIntentKind.goBack:
        bridge.popRestaurantRoute?.call();
        return _speak('Going back.');

      case VoiceIntentKind.whereAmI:
        final desc = bridge.describeVoiceLocation?.call();
        return _speak(desc ?? 'You are in SpeakDine.');

      case VoiceIntentKind.trackOrderIntent:
        return _handleVoiceTabShortcut(VoiceTabShortcut.trackOrder);

      case VoiceIntentKind.suggestNextAction:
        final hint = (r.extractedQuery ?? '').trim();
        if (hint == VoiceIntentResult.suggestRepeatLast) {
          if (_lastSpoken.isEmpty) {
            return _speak('Nothing to repeat yet.');
          }
          return _speak(_lastSpoken);
        }
        final lower = hint.toLowerCase();
        if (lower.contains('cart')) {
          switchToTab(tabCart);
          return _speak('Cart.');
        }
        if (lower.contains('order')) {
          switchToTab(tabOrders);
          return _speak('Orders.');
        }
        if (lower.contains('profile') || lower.contains('account')) {
          switchToTab(tabProfile);
          return _speak('Profile.');
        }
        if (lower.contains('pay') || lower.contains('transaction')) {
          switchToTab(tabPayments);
          return _speak('Payments.');
        }
        if (lower.contains('home') || lower.contains('restaurant')) {
          switchToTab(tabHome);
          bridge.resetRestaurantStack?.call();
          return _speak('Home page.');
        }
        return _speak(
          'Try: add to cart with a dish name, open cart, go home, or confirm add on a menu.',
        );

      case VoiceIntentKind.clarifyUserIntent:
        return _speak(
          'Say that another way. For example: add pizza to cart, open cart, or confirm add.',
        );

      case VoiceIntentKind.cancelCurrentFlow:
        _clearVoiceFlow(bridge);
        return _speak('Stopped. Say what you would like to do next.');
    }
  }
}

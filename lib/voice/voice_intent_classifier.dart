import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/voice/voice_intent_models.dart';

/// Rule-based fallback when Gemini is unavailable.
class VoiceIntentClassifier {
  const VoiceIntentClassifier();

  VoiceIntentResult classify(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) {
      return VoiceIntentResult.empty;
    }

    final offTopic = _strongOffTopic(lower);
    final foodHint = _hasFoodOrAppHint(lower);

    VoiceIntentResult? hit;

    hit ??= _cancel(lower);
    hit ??= _trackOrder(lower);
    hit ??= _repeat(lower);
    hit ??= _goBack(lower);
    hit ??= _goHome(lower);
    hit ??= _whereAmI(lower);
    hit ??= _openCart(lower);
    hit ??= _checkout(lower);
    hit ??= _settings(lower, raw);
    hit ??= _ambiguousOrder(lower);
    hit ??= _confirmAdd(lower);
    hit ??= _addToCartVague(lower, raw);
    hit ??= _addToCartExplicit(lower, raw);
    hit ??= _selectMenu(lower, raw);
    hit ??= _category(lower);
    hit ??= _cartNaturalLanguage(lower, raw);
    hit ??= _classifyChangeUserNameAsUpdate(lower, raw);

    if (hit != null) {
      return hit;
    }

    if (offTopic && !foodHint) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.nonFood,
        isFoodOrOrderingRelated: false,
        confidence: 0.85,
      );
    }

    return VoiceIntentResult(
      kind: VoiceIntentKind.unknown,
      isFoodOrOrderingRelated: foodHint || !offTopic,
      confidence: 0.35,
      extractedQuery: raw.trim(),
    );
  }

  VoiceIntentResult? _cancel(String lower) {
    if (_matches(lower, [
      'cancel that',
      'cancel it',
      'stop',
      'never mind',
      'nevermind',
      'forget it',
      'leave it',
    ])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.cancelAction,
        isFoodOrOrderingRelated: true,
        confidence: 0.9,
      );
    }
    if (_matches(lower, [
      'cancel checkout',
      'stop checkout',
      'abort checkout',
    ])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.cancelCheckout,
        isFoodOrOrderingRelated: true,
        confidence: 0.85,
      );
    }
    if (_matches(lower, ['cancel flow', 'stop this', 'reset'])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.cancelCurrentFlow,
        isFoodOrOrderingRelated: true,
        confidence: 0.82,
      );
    }
    return null;
  }

  VoiceIntentResult? _trackOrder(String lower) {
    if (_matches(lower, [
      'track order',
      'track my order',
      'track the order',
      'where is my order',
      'where is the order',
      'where my order',
      'order status',
      'order tracking',
      'delivery status',
      'see where my order',
      'see where the order',
      'want to see where',
      'see where order',
    ])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.trackOrderIntent,
        isFoodOrOrderingRelated: true,
        confidence: 0.88,
      );
    }
    return null;
  }

  VoiceIntentResult? _repeat(String lower) {
    if (_matches(lower, [
      'repeat that',
      'say that again',
      'repeat last',
      'what did you say',
      'repeat again',
      'repeat agin',
      'repeat the instructions again',
      'repeat instructions',
    ])) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.suggestNextAction,
        isFoodOrOrderingRelated: true,
        confidence: 0.88,
        extractedQuery: VoiceIntentResult.suggestRepeatLast,
      );
    }
    return null;
  }

  VoiceIntentResult? _goBack(String lower) {
    if (_matches(lower, ['go back', 'take me back', 'previous screen'])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.goBack,
        isFoodOrOrderingRelated: true,
        confidence: 0.88,
      );
    }
    return null;
  }

  VoiceIntentResult? _goHome(String lower) {
    if (_matches(lower, [
      'go home',
      'home screen',
      'restaurant list',
      'show restaurants',
    ])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.goHome,
        isFoodOrOrderingRelated: true,
        confidence: 0.88,
      );
    }
    return null;
  }

  VoiceIntentResult? _whereAmI(String lower) {
    if (_matches(lower, ['where am i', 'which screen', 'which tab'])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.whereAmI,
        isFoodOrOrderingRelated: true,
        confidence: 0.9,
      );
    }
    return null;
  }

  VoiceIntentResult? _openCart(String lower) {
    if (_matches(lower, [
          'open cart',
          'show cart',
          'my cart',
          'shopping cart',
          'cart kholo',
          'cart dekhao',
        ]) ||
        lower == 'cart') {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.openCartIntent,
        isFoodOrOrderingRelated: true,
        confidence: 0.88,
      );
    }
    return null;
  }

  VoiceIntentResult? _checkout(String lower) {
    if (_matches(lower, [
      'place order',
      'place my order',
      'place the order',
      'checkout',
      'check out',
      'pay now',
      'make payment',
      'confirm order',
      'complete order',
    ])) {
      if (lower.contains('tap') || lower.contains('button')) {
        return const VoiceIntentResult(
          kind: VoiceIntentKind.confirmOrderUIOnly,
          isFoodOrOrderingRelated: true,
          confidence: 0.8,
        );
      }
      if (lower.contains('confirm') && !lower.contains('add')) {
        return const VoiceIntentResult(
          kind: VoiceIntentKind.confirmOrderUIOnly,
          isFoodOrOrderingRelated: true,
          confidence: 0.78,
        );
      }
      return const VoiceIntentResult(
        kind: VoiceIntentKind.initiateCheckout,
        isFoodOrOrderingRelated: true,
        confidence: 0.82,
      );
    }
    return null;
  }

  VoiceIntentResult? _settings(String lower, String raw) {
    if (_matches(lower, ['open settings', 'settings', 'app settings'])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.openSettings,
        isFoodOrOrderingRelated: true,
        confidence: 0.82,
      );
    }
    if (_matches(lower, [
      'turn on notifications',
      'turn off notifications',
      'enable location',
      'disable location',
      'toggle',
    ])) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.toggleSetting,
        isFoodOrOrderingRelated: true,
        confidence: 0.75,
        extractedQuery: raw.trim(),
      );
    }
    return null;
  }

  VoiceIntentResult? _classifyChangeUserNameAsUpdate(String lower, String raw) {
    const prefixes = [
      'change my name to ',
      'set my name to ',
      'update my name to ',
      'call me ',
      'my name is ',
    ];
    for (final p in prefixes) {
      if (!lower.startsWith(p)) {
        continue;
      }
      if (raw.length < p.length) {
        continue;
      }
      final name = raw.substring(p.length).trim();
      if (name.isEmpty) {
        continue;
      }
      return VoiceIntentResult(
        kind: VoiceIntentKind.updateSettingValue,
        isFoodOrOrderingRelated: true,
        confidence: 0.86,
        settingKey: 'username',
        settingValue: name,
      );
    }
    return null;
  }

  VoiceIntentResult? _ambiguousOrder(String lower) {
    if (lower == 'order' ||
        (lower.contains('order') &&
            !lower.contains('cart') &&
            !lower.contains('track') &&
            lower.split(RegExp(r'\s+')).length <= 3)) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.ambiguousOrderIntent,
        isFoodOrOrderingRelated: true,
        confidence: 0.55,
      );
    }
    return null;
  }

  VoiceIntentResult? _confirmAdd(String lower) {
    if (_matches(lower, [
          'confirm add',
          'add this',
          'add it',
          'yes add',
          'put it in cart',
          'add to my cart',
          'confirm',
        ]) &&
        !lower.contains('order') &&
        !lower.contains('place')) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.confirmAddToCart,
        isFoodOrOrderingRelated: true,
        confidence: 0.84,
      );
    }
    return null;
  }

  VoiceIntentResult? _addToCartVague(String lower, String raw) {
    if (_matches(lower, ['add that', 'get that', 'i want that'])) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.addToCartIntent,
        isFoodOrOrderingRelated: true,
        confidence: 0.65,
        extractedQuery: raw.trim(),
      );
    }
    return null;
  }

  VoiceIntentResult? _addToCartExplicit(String lower, String raw) {
    if (!_matches(lower, [
          'add to cart',
          'add in cart',
          'cart mein',
          'cart me ',
          'put in cart',
        ]) &&
        !(lower.contains('add') && lower.contains('cart'))) {
      return null;
    }
    final item = _extractItemNameForAddToCart(lower);
    return VoiceIntentResult(
      kind: VoiceIntentKind.addToCartRequest,
      isFoodOrOrderingRelated: true,
      confidence: 0.82,
      itemName: item,
      extractedQuery: raw.trim(),
    );
  }

  VoiceIntentResult? _selectMenu(String lower, String raw) {
    if (_matches(lower, [
      'open ',
      'kholo ',
      'go to ',
      'show menu',
      'menu of ',
    ])) {
      final name = _extractRestaurantName(lower);
      if (name != null && name.isNotEmpty) {
        return VoiceIntentResult(
          kind: VoiceIntentKind.selectMenuItem,
          isFoodOrOrderingRelated: true,
          confidence: 0.72,
          restaurantName: name,
          extractedQuery: raw.trim(),
        );
      }
    }
    if (_isDishLike(lower, raw)) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.selectMenuItem,
        isFoodOrOrderingRelated: true,
        confidence: 0.55,
        itemName: raw.trim(),
        extractedQuery: raw.trim(),
      );
    }
    return null;
  }

  VoiceIntentResult? _category(String lower) {
    for (final c in kSdLibRestaurantCategories) {
      if (lower.contains(c.label.toLowerCase())) {
        return VoiceIntentResult(
          kind: VoiceIntentKind.selectMenuItem,
          isFoodOrOrderingRelated: true,
          confidence: 0.74,
          categoryId: c.id,
          extractedQuery: c.label,
        );
      }
    }
    return null;
  }

  VoiceIntentResult? _cartNaturalLanguage(String lower, String raw) {
    if (!_looksLikeCartNaturalLanguageEdit(lower)) {
      return null;
    }
    return VoiceIntentResult(
      kind: VoiceIntentKind.cartNaturalLanguageEdit,
      isFoodOrOrderingRelated: true,
      confidence: 0.82,
      extractedQuery: raw.trim(),
    );
  }

  bool _looksLikeCartNaturalLanguageEdit(String lower) {
    if (RegExp(
      r'\b(remove|delete|take out|get rid of|drop)\b',
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'\b(one less|decrease|reduce|remove one|minus one)\b',
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'\b(one more|another|add one more|add another|add more|extra)\b',
    ).hasMatch(lower)) {
      return true;
    }
    final multi = lower.contains(' and ') || lower.contains(',');
    if (!multi) {
      return false;
    }
    if (RegExp(
      r'\b(remove|delete|take out|add one more|add another|add more|one more|another)\b',
    ).hasMatch(lower)) {
      return true;
    }
    return lower.contains('add ') && !lower.contains(' to cart');
  }

  bool _isDishLike(String lower, String raw) {
    if (raw.split(RegExp(r'\s+')).length > 8) {
      return false;
    }
    return _matches(lower, [
      'burger',
      'pizza',
      'biryani',
      'karahi',
      'coffee',
      'chai',
      'roll',
      'paratha',
      'nihari',
      'bbq',
    ]);
  }

  bool _strongOffTopic(String lower) {
    return _matches(lower, ['weather', 'cricket', 'bitcoin', 'stock price']);
  }

  bool _hasFoodOrAppHint(String lower) {
    return _matches(lower, [
      'food',
      'eat',
      'restaurant',
      'menu',
      'cart',
      'order',
      'delivery',
      'burger',
      'pizza',
      'add',
      'checkout',
      'pay',
      'setting',
      'home',
      'profile',
    ]);
  }

  bool _matches(String lower, List<String> phrases) {
    for (final p in phrases) {
      if (lower.contains(p)) {
        return true;
      }
    }
    return false;
  }

  String? _extractRestaurantName(String lower) {
    const prefixes = ['open ', 'kholo ', 'go to ', 'menu of ', 'restaurant '];
    for (final pre in prefixes) {
      if (lower.contains(pre)) {
        final start = lower.indexOf(pre) + pre.length;
        var rest = lower.substring(start).trim();
        final words = rest.split(RegExp(r'\s+'));
        if (words.isNotEmpty && words[0].length > 2) {
          return words[0];
        }
      }
    }
    return null;
  }

  String? _extractItemNameForAddToCart(String lower) {
    var without = lower;
    for (final p in [
      'add to cart',
      'add in cart',
      'put in cart',
      'cart mein',
      'cart me',
    ]) {
      without = without.replaceAll(p, ' ');
    }
    without = without.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (without.length > 1) {
      return without;
    }
    return null;
  }
}

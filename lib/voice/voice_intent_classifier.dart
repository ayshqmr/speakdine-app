import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/voice/voice_intent_models.dart';

/// Rule-based classifier: food/ordering gate + [VoiceIntentKind].
///
/// Replace the body with an on-device or cloud model later; keep [VoiceIntentResult] stable.
class VoiceIntentClassifier {
  const VoiceIntentClassifier();

  VoiceIntentResult classify(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) return VoiceIntentResult.empty;

    final offTopic = _strongOffTopic(lower);
    final foodHint = _hasFoodOrAppHint(lower);

    if (offTopic && !foodHint) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.nonFood,
        isFoodOrOrderingRelated: false,
        confidence: 0.85,
      );
    }

    // 1) Profile / account
    final profile = _classifyUserProfile(lower);
    if (profile != null) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.userProfile,
        isFoodOrOrderingRelated: true,
        confidence: 0.82,
        extractedQuery: raw.trim(),
      );
    }

    // 2) Order / cart / payment
    final order = _classifyOrderPlacement(lower, raw);
    if (order != null) return order;

    // 3) Category browse (SD-lib)
    final cat = _classifyCategory(lower);
    if (cat != null) return cat;

    // 4) Dish description
    if (_isDishDescription(lower)) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.dishDescription,
        isFoodOrOrderingRelated: true,
        confidence: 0.72,
        extractedQuery: _stripQuestionPhrases(lower, raw.trim()),
      );
    }

    // 5) Restaurant info (hours, address, open…)
    if (_isRestaurantInfo(lower)) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.restaurantInfo,
        isFoodOrOrderingRelated: true,
        confidence: 0.74,
        extractedQuery: raw.trim(),
      );
    }

    // 6) Open restaurant / order at X (from voice-feature style)
    final openRest = _extractRestaurantName(lower);
    if (openRest != null && openRest.isNotEmpty) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.restaurantInfo,
        isFoodOrOrderingRelated: true,
        confidence: 0.68,
        restaurantName: openRest,
        itemName: _extractItemNameFromOrderPhrase(lower),
        extractedQuery: raw.trim(),
      );
    }

    // 7) Short phrase → likely dish add / search
    final words = lower.split(RegExp(r'\s+'));
    if (words.isNotEmpty && words.length <= 6) {
      const skip = {
        'the', 'a', 'an', 'ye', 'wo', 'yeh', 'this', 'that',
        'karo', 'karna', 'chahiye', 'please', 'mujhe', 'meri', 'mera',
      };
      final meaningful =
          words.where((w) => w.length >= 2 && !skip.contains(w)).toList();
      if (meaningful.isNotEmpty && foodHint) {
        return VoiceIntentResult(
          kind: VoiceIntentKind.dishDescription,
          isFoodOrOrderingRelated: true,
          confidence: 0.45,
          itemName: raw.trim(),
          extractedQuery: raw.trim(),
        );
      }
    }

    final related = foodHint || !offTopic;
    return VoiceIntentResult(
      kind: VoiceIntentKind.unknown,
      isFoodOrOrderingRelated: related,
      confidence: 0.35,
      extractedQuery: raw.trim(),
    );
  }

  bool _strongOffTopic(String lower) {
    return _matches(lower, [
      'weather',
      'temperature today',
      'rain today',
      'cricket score',
      'football match',
      'stock price',
      'bitcoin',
      'who is the president',
      'what time is it in',
      'translate ',
      'calculate ',
    ]);
  }

  bool _hasFoodOrAppHint(String lower) {
    return _matches(lower, [
      'food', 'eat', 'eating', 'hungry', 'restaurant', 'cafe', 'café',
      'menu', 'dish', 'meal', 'breakfast', 'lunch', 'dinner', 'snack',
      'order', 'cart', 'checkout', 'delivery', 'biryani', 'burger', 'pizza',
      'karahi', 'nihari', 'halal', 'spicy', 'sweet', 'coffee', 'chai',
      'desi', 'fast food', 'bbq', 'seafood', 'pay', 'payment', 'profile',
      'address', 'my orders', 'saved card',
    ]);
  }

  VoiceIntentResult? _classifyUserProfile(String lower) {
    if (_matches(lower, [
      'my profile', 'my account', 'open profile', 'profile kholo',
      'mera profile', 'meri profile', 'account settings',
      'my name', 'mera naam', 'my email', 'my phone', 'mera phone',
      'my address', 'mera address', 'delivery address', 'my location',
      'my orders', 'meray orders', 'order history', 'past orders',
      'my payments', 'saved card', 'payment methods', 'my cards',
    ])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.userProfile,
        isFoodOrOrderingRelated: true,
        confidence: 0.8,
      );
    }
    return null;
  }

  VoiceIntentResult? _classifyOrderPlacement(String lower, String raw) {
    if (_matches(lower, [
      'show cart', 'open cart', 'cart dekhao', 'cart dikhao', 'cart kholo',
      'my cart', 'shopping cart',
    ]) || (lower == 'cart' || lower.startsWith('cart '))) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.orderPlacement,
        isFoodOrOrderingRelated: true,
        confidence: 0.88,
      );
    }

    if (_matches(lower, [
      'place order', 'order place', 'place krdo', 'place kar do',
      'confirm order', 'order confirm', 'order place karo', 'order lagao',
      'checkout', 'check out', 'pay now', 'make payment', 'payment karo',
    ]) || (lower.contains('place') && lower.contains('order'))) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.orderPlacement,
        isFoodOrOrderingRelated: true,
        confidence: 0.84,
      );
    }

    if (_matches(lower, ['pay', 'payment', 'checkout'])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.orderPlacement,
        isFoodOrOrderingRelated: true,
        confidence: 0.78,
      );
    }

    final addToCart = _matches(lower, [
      'add to cart', 'cart mein dalo', 'cart me dalo', 'add to cart karo',
      'isko add krdo', 'isko add karo', 'add krdo', 'add kardo', 'ye add krdo',
      'ye cart mein add kro', 'ye cart me add kro', 'cart mein add kro',
      'cart me add kro', 'is ko cart mein add kro', 'isko cart mein add kro',
      'ye cart add kro', 'cart add kro', 'cart add karo', 'add karo cart',
      'cart mein add karo',
    ]);
    if (addToCart ||
        (lower.contains('cart') &&
            (lower.contains('add') ||
                lower.contains('dal') ||
                lower.contains('kro') ||
                lower.contains('karo'))) ||
        (lower.contains('add') &&
            (lower.contains('cart') ||
                lower.contains('dal') ||
                lower.contains('karo')))) {
      return VoiceIntentResult(
        kind: VoiceIntentKind.orderPlacement,
        isFoodOrOrderingRelated: true,
        confidence: 0.8,
        itemName: _extractItemNameForAddToCart(lower),
        extractedQuery: raw.trim(),
      );
    }

    if (lower.contains('menu') &&
        (lower.contains('what') ||
            lower.contains('list') ||
            lower.contains('read') ||
            lower.contains('kya') ||
            lower.contains('batao') ||
            lower.contains('sunao'))) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.restaurantInfo,
        isFoodOrOrderingRelated: true,
        confidence: 0.7,
      );
    }

    return null;
  }

  VoiceIntentResult? _classifyCategory(String lower) {
    for (final c in kSdLibRestaurantCategories) {
      final labelLower = c.label.toLowerCase();
      if (lower.contains(labelLower)) {
        return VoiceIntentResult(
          kind: VoiceIntentKind.categoryBrowse,
          isFoodOrOrderingRelated: true,
          confidence: 0.77,
          categoryId: c.id,
          extractedQuery: c.label,
        );
      }
      // id-style mentions
      if (lower.contains(c.id.replaceAll('_', ' '))) {
        return VoiceIntentResult(
          kind: VoiceIntentKind.categoryBrowse,
          isFoodOrOrderingRelated: true,
          confidence: 0.72,
          categoryId: c.id,
        );
      }
    }
    if (_matches(lower, [
      'desi food', 'fast food places', 'pizza places', 'cafe near',
      'bakery near', 'asian food', 'bbq places', 'seafood restaurant',
      'healthy food', 'dessert place', 'bar food', 'fine dining',
      'street food',
    ])) {
      return const VoiceIntentResult(
        kind: VoiceIntentKind.categoryBrowse,
        isFoodOrOrderingRelated: true,
        confidence: 0.55,
      );
    }
    return null;
  }

  bool _isDishDescription(String lower) {
    return _matches(lower, [
      'what is ', 'what\'s ', 'whats ',
      'ingredients', 'recipe', 'spicy', 'halal', 'vegan', 'vegetarian',
      'calories', 'price of', 'how much is', 'kitnay', 'kya hai',
      'describe ', 'tell me about', 'dish', 'batao is', 'ye kya',
    ]);
  }

  bool _isRestaurantInfo(String lower) {
    return _matches(lower, [
      'opening hours', 'open now', 'closed', 'when do you open',
      'business hours', 'timings', 'address', 'location', 'where is',
      'phone number', 'contact', 'directions', 'map',
      'about this restaurant', 'restaurant info',
    ]);
  }

  String _stripQuestionPhrases(String lower, String raw) {
    var s = raw.trim();
    for (final p in [
      'what is ', 'what\'s ', 'whats ', 'tell me about ', 'describe ',
    ]) {
      if (lower.startsWith(p)) {
        s = raw.substring(p.length).trim();
        break;
      }
    }
    return s.isEmpty ? raw.trim() : s;
  }

  bool _matches(String lower, List<String> phrases) {
    for (final p in phrases) {
      if (lower.contains(p)) return true;
    }
    return false;
  }

  String? _extractRestaurantName(String lower) {
    if (lower.contains('mujhe') && lower.contains('order')) {
      final withoutMujhe = lower.replaceFirst('mujhe', '').trim();
      final words = withoutMujhe.split(RegExp(r'\s+'));
      for (var i = 0; i < words.length; i++) {
        if (words[i] == 'ka' || words[i] == 'ke') continue;
        if (words[i].contains('order')) break;
        if (words[i].length > 2) return words[i];
      }
    }
    const prefixes = [
      'open ',
      'kholo ',
      'menu mein ',
      'menu me ',
      'restaurant ',
      'go to ',
    ];
    for (final pre in prefixes) {
      if (lower.contains(pre)) {
        final start = lower.indexOf(pre) + pre.length;
        var rest = lower.substring(start).trim();
        if (rest.isEmpty) continue;
        final words = rest.split(RegExp(r'\s+'));
        if (words.isNotEmpty && words[0].length > 2) return words[0];
      }
    }
    final words = lower.split(RegExp(r'\s+'));
    if (words.length == 1 && words[0].length > 2) return words[0];
    if (words.length >= 2 &&
        (words[1] == 'kholo' ||
            words[1] == 'menu' ||
            words[1] == 'open')) {
      return words[0];
    }
    return null;
  }

  String? _extractItemNameForAddToCart(String lower) {
    var without = lower;
    const addPatterns = [
      'add to cart',
      'add in cart',
      'put in cart',
      'add krdo',
      'add karo',
      'cart mein dalo',
      'cart me add',
      'isko add',
    ];
    for (final p in addPatterns) {
      without = without.replaceAll(p, ' ');
    }
    without = without.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (without.length > 1) return without;
    return null;
  }

  String? _extractItemNameFromOrderPhrase(String lower) {
    if (!lower.contains('order')) return null;
    final parts = lower.split(RegExp(r'\s+order\s+'));
    if (parts.isNotEmpty) {
      final before = parts[0].trim();
      final words = before.split(RegExp(r'\s+'));
      const skip = {'mujhe', 'main', 'ka', 'ke', 'mein', 'me'};
      final list =
          words.where((w) => w.length > 1 && !skip.contains(w)).toList();
      if (list.isNotEmpty) return list.join(' ');
    }
    return null;
  }
}

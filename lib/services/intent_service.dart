/// Result of voice intent detection: action + optional entity names.
class VoiceIntent {
  final String action;
  final String? restaurantName;
  final String? itemName;

  const VoiceIntent({
    required this.action,
    this.restaurantName,
    this.itemName,
  });

  static const unknown = VoiceIntent(action: 'UNKNOWN');
}

class IntentService {
  /// Detects intent from spoken text. Returns action and optional restaurant/item names.
  VoiceIntent detectIntent(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return VoiceIntent.unknown;

    // SHOW_CART: "cart dekhao", "cart dikhao", "cart", "show cart"
    if (_matches(lower, [
      'cart dekhao', 'cart dikhao', 'cart dikha', 'cart dekha',
      'show cart', 'open cart', 'cart', 'cart kholo'
    ])) {
      return const VoiceIntent(action: 'SHOW_CART');
    }

    // PLACE_ORDER: "place order", "order place krdo", "place krdo", "confirm order"
    if (_matches(lower, [
      'place order', 'order place', 'place krdo', 'place kar do',
      'confirm order', 'order confirm', 'order place karo', 'order lagao'
    ]) || lower.contains('place') && lower.contains('order')) {
      return const VoiceIntent(action: 'PLACE_ORDER');
    }

    // MAKE_PAYMENT: pay, payment, checkout
    if (_matches(lower, [
      'pay', 'payment', 'checkout', 'payment karo'
    ])) {
      return const VoiceIntent(action: 'MAKE_PAYMENT');
    }

    // ADD_TO_CART: "add to cart", "ye cart mein add kro", "cart mein dalo", "isko add krdo", etc.
    final addToCart = _matches(lower, [
      'add to cart', 'cart mein dalo', 'cart me dalo', 'add to cart karo',
      'isko add krdo', 'isko add karo', 'add krdo', 'add kardo', 'ye add krdo',
      'ye cart mein add kro', 'ye cart me add kro', 'cart mein add kro', 'cart me add kro',
      'is ko cart mein add kro', 'isko cart mein add kro', 'ye cart add kro',
      'cart add kro', 'cart add karo', 'add karo cart', 'cart mein add karo'
    ]);
    if (addToCart) {
      final itemName = _extractItemNameForAddToCart(lower);
      return VoiceIntent(action: 'ADD_TO_CART', itemName: itemName);
    }
    // "ye cart mein add kro" type: cart + add/dal/kro/karo
    if (lower.contains('cart') && (lower.contains('add') || lower.contains('dal') || lower.contains('kro') || lower.contains('karo'))) {
      final itemName = _extractItemNameForAddToCart(lower);
      return VoiceIntent(action: 'ADD_TO_CART', itemName: itemName);
    }
    if (lower.contains('add') && (lower.contains('cart') || lower.contains('dal') || lower.contains('karo'))) {
      final itemName = _extractItemNameForAddToCart(lower);
      return VoiceIntent(action: 'ADD_TO_CART', itemName: itemName);
    }

    // TELL_MENU: "what's in the menu", "list menu", "read menu", "menu kya hai", etc.
    if (_matches(lower, [
      'what\'s in the menu', 'whats in the menu', 'what is in the menu',
      'list menu', 'list the menu', 'read menu', 'tell me the menu',
      'menu kya hai', 'menu mein kya hai', 'batao', 'batao menu',
      'menu batao', 'menu dikhao', 'menu sunao'
    ]) || (lower.contains('menu') && (lower.contains('what') || lower.contains('list') || lower.contains('read') || lower.contains('kya') || lower.contains('batao')))) {
      return const VoiceIntent(action: 'TELL_MENU');
    }

    // OPEN_RESTAURANT: "KFC kholo", "menu mein KFC", "KFC restaurant", "open KFC", or "mujhe X order karna" -> X
    final openRest = _extractRestaurantName(lower);
    if (openRest != null && openRest.isNotEmpty) {
      return VoiceIntent(action: 'OPEN_RESTAURANT', restaurantName: openRest, itemName: _extractItemNameFromOrderPhrase(lower));
    }

    // Legacy: SHOW_MENU = stay on home / show restaurants list
    if (lower.contains('menu')) {
      return const VoiceIntent(action: 'SHOW_MENU');
    }

    // Legacy: "order" alone = open cart
    if (lower.contains('order')) {
      return const VoiceIntent(action: 'PLACE_ORDER');
    }

    // On restaurant screen: saying just an item name (e.g. "wer", "burger", "chicken burger") = add that item to cart
    final words = lower.split(RegExp(r'\s+'));
    if (words.isNotEmpty && words.length <= 5) {
      final skipWords = {'the', 'a', 'an', 'ye', 'wo', 'this', 'that', 'karo', 'karna', 'chahiye'};
      final meaningful = words.where((w) => w.length >= 2 && !skipWords.contains(w)).toList();
      if (meaningful.isNotEmpty) {
        return VoiceIntent(action: 'ADD_TO_CART', itemName: text.trim());
      }
    }

    return VoiceIntent.unknown;
  }

  bool _matches(String lower, List<String> phrases) {
    for (final p in phrases) {
      if (lower.contains(p)) return true;
    }
    return false;
  }

  /// Extract restaurant name: e.g. "kfc kholo" -> "kfc", "menu mein kfc" -> "kfc", "mujhe kfc ka burger order" -> "kfc"
  String? _extractRestaurantName(String lower) {
    // "mujhe KFC ka chicken burger order karna hai" -> restaurant "kfc"
    if (lower.contains('mujhe') && lower.contains('order')) {
      final withoutMujhe = lower.replaceFirst('mujhe', '').trim();
      final words = withoutMujhe.split(RegExp(r'\s+'));
      for (int i = 0; i < words.length; i++) {
        if (words[i] == 'ka' || words[i] == 'ke') continue;
        if (words[i].contains('order')) break;
        if (words[i].length > 2) return words[i]; // first substantial word = restaurant
      }
    }
    const prefixes = [
      'open ', 'kholo ', 'menu mein ', 'menu me ', 'restaurant ', 'go to '
    ];
    for (final pre in prefixes) {
      if (lower.startsWith(pre) || lower.contains(pre)) {
        int start = lower.indexOf(pre) + pre.length;
        String rest = lower.substring(start).trim();
        if (rest.isEmpty) continue;
        final words = rest.split(RegExp(r'\s+'));
        if (words.isNotEmpty && words[0].length > 2) return words[0];
      }
    }
    final words = lower.split(RegExp(r'\s+'));
    if (words.length == 1 && words[0].length > 2) return words[0];
    if (words.length >= 2 && (words[1] == 'kholo' || words[1] == 'menu' || words[1] == 'open')) return words[0];
    return null;
  }

  /// From "add chicken burger to cart" or "chicken burger add krdo" -> "chicken burger"
  String? _extractItemNameForAddToCart(String lower) {
    final addPatterns = ['add to cart', 'add in cart', 'put in cart', 'add krdo', 'add karo', 'cart mein dalo', 'cart me add', 'isko add'];
    String without = lower;
    for (final p in addPatterns) {
      without = without.replaceAll(p, ' ').trim();
    }
    without = without.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (without.length > 1) return without;
    return null;
  }

  /// From "mujhe kfc ka chicken burger order karna hai" -> "chicken burger"
  String? _extractItemNameFromOrderPhrase(String lower) {
    if (!lower.contains('order') && !lower.contains('order')) return null;
    final parts = lower.split(RegExp(r'\s+order\s*'));
    if (parts.length >= 1) {
      String before = parts[0].trim();
      final words = before.split(RegExp(r'\s+'));
      // drop "mujhe", "main", "ka", "ke" and take rest as item
      final skip = {'mujhe', 'main', 'ka', 'ke', 'kfc', 'mein', 'me'};
      final list = words.where((w) => w.length > 1 && !skip.contains(w)).toList();
      if (list.isNotEmpty) return list.join(' ');
    }
    return null;
  }
}

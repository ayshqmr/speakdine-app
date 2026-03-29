// Global cart service to manage cart state across the app

class CartService {
  // Singleton pattern
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  // Cart: Map of restaurantId -> list of items
  final Map<String, List<Map<String, dynamic>>> cart = {};

  // Get total items count
  int get totalItems {
    int count = 0;
    cart.forEach((key, items) {
      for (var item in items) {
        count += (item['quantity'] as int? ?? 1);
      }
    });
    return count;
  }

  // Get total amount
  double get totalAmount {
    double total = 0;
    cart.forEach((restaurantId, items) {
      for (var item in items) {
        total += (item['price'] ?? 0) * (item['quantity'] ?? 1);
      }
    });
    return total;
  }

  // Add item to cart
  void addItem(String restaurantId, String restaurantName, Map<String, dynamic> item, String itemId) {
    // Initialize cart for this restaurant if not exists
    if (!cart.containsKey(restaurantId)) {
      cart[restaurantId] = [];
    }

    // Check if item already in cart
    final existingIndex = cart[restaurantId]!
        .indexWhere((cartItem) => cartItem['itemId'] == itemId);

    if (existingIndex >= 0) {
      // Increase quantity
      cart[restaurantId]![existingIndex]['quantity']++;
    } else {
      // Add new item
      cart[restaurantId]!.add({
        'itemId': itemId,
        'name': item['name'],
        'price': item['price'],
        'description': item['description'],
        'quantity': 1,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
      });
    }
  }

  // Increase quantity
  void increaseQuantity(String restaurantId, int index) {
    cart[restaurantId]![index]['quantity']++;
  }

  // Decrease quantity
  void decreaseQuantity(String restaurantId, int index) {
    if (cart[restaurantId]![index]['quantity'] > 1) {
      cart[restaurantId]![index]['quantity']--;
    } else {
      // Remove item
      cart[restaurantId]!.removeAt(index);
      // Remove restaurant if empty
      if (cart[restaurantId]!.isEmpty) {
        cart.remove(restaurantId);
      }
    }
  }

  // Remove item
  void removeItem(String restaurantId, int index) {
    cart[restaurantId]!.removeAt(index);
    if (cart[restaurantId]!.isEmpty) {
      cart.remove(restaurantId);
    }
  }

  // Clear cart
  void clearCart() {
    cart.clear();
  }

  // Get quantity for specific item
  int getItemQuantity(String restaurantId, String itemId) {
    if (!cart.containsKey(restaurantId)) return 0;
    final cartItem = cart[restaurantId]!
        .where((ci) => ci['itemId'] == itemId)
        .toList();
    if (cartItem.isNotEmpty) {
      return cartItem.first['quantity'] ?? 0;
    }
    return 0;
  }

  // Check if cart is empty
  bool get isEmpty => cart.isEmpty;

  // Check if cart is not empty
  bool get isNotEmpty => cart.isNotEmpty;
}

// Global instance
final cartService = CartService();


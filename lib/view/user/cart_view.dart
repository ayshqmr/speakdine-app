import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/services/payment_service.dart';
import 'package:speak_dine/utils/pkr_format.dart';
import 'package:speak_dine/services/notification_service.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/widgets/customer_voice_fab.dart';

class CartView extends StatefulWidget {
  final bool embedded;

  const CartView({super.key, this.embedded = false});

  @override
  State<CartView> createState() => _CartViewState();
}

class _CartViewState extends State<CartView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _placingOrder = false;

  void _increaseQuantity(String restaurantId, int index) {
    setState(() => cartService.increaseQuantity(restaurantId, index));
  }

  void _decreaseQuantity(String restaurantId, int index) {
    setState(() => cartService.decreaseQuantity(restaurantId, index));
  }

  void _editCustomizationNote(
    ThemeData theme,
    String restaurantId,
    int index,
    Map<String, dynamic> item,
  ) {
    final name = (item['name'] ?? 'item').toString();
    final initial = (item['note'] ?? '').toString();
    final controller = TextEditingController(text: initial);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Customisation for $name'),
        content: SizedBox(
          width: 340,
          child: TextField(
            controller: controller,
            placeholder: const Text('Example: no onions, extra spicy'),
            maxLines: 3,
          ),
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlineButton(
            onPressed: () {
              setState(() {
                cartService.updateItemNote(restaurantId, index, '');
              });
              Navigator.pop(ctx);
            },
            child: Text(
              'Clear',
              style: TextStyle(color: theme.colorScheme.destructive),
            ),
          ),
          PrimaryButton(
            onPressed: () {
              setState(() {
                cartService.updateItemNote(
                  restaurantId,
                  index,
                  controller.text.trim(),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static const _stripeMinimumPkr = 150.0;

  @override
  void initState() {
    super.initState();
    final bridge = CustomerVoiceBridge.instance;
    bridge.voiceFullCartSummary = _voiceFullCartSummary;
    bridge.placeVoiceOrderWithPayment = _placeOrderFromVoice;
    bridge.showCartPaymentMethodDialog = _showPaymentMethodDialog;
  }

  @override
  void dispose() {
    final bridge = CustomerVoiceBridge.instance;
    if (bridge.voiceFullCartSummary == _voiceFullCartSummary) {
      bridge.voiceFullCartSummary = null;
    }
    if (bridge.placeVoiceOrderWithPayment == _placeOrderFromVoice) {
      bridge.placeVoiceOrderWithPayment = null;
    }
    if (bridge.showCartPaymentMethodDialog == _showPaymentMethodDialog) {
      bridge.showCartPaymentMethodDialog = null;
    }
    super.dispose();
  }

  String _voiceFullCartSummary() {
    if (cartService.isEmpty) {
      return 'Your cart is empty.';
    }
    final parts = <String>[];
    for (final entry in cartService.cart.entries) {
      for (final item in entry.value) {
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final q = item['quantity'];
        var qty = 1;
        if (q is num) {
          qty = q.toInt().clamp(1, 999);
        }
        parts.add('$qty ${qty == 1 ? name : '${name}s'}');
      }
    }
    final total = formatPkr(cartService.totalAmount);
    return 'Your cart has: ${parts.join(', ')}. Total is $total.';
  }

  Future<String?> _placeOrderFromVoice(String method) async {
    final bridge = CustomerVoiceBridge.instance;
    final normalized = method.toLowerCase().trim();
    if (normalized != 'cod' && normalized != 'online') {
      return 'Please choose cash on delivery or online payment.';
    }
    if (_placingOrder) {
      return 'Your order is already being placed.';
    }
    if (cartService.isEmpty) {
      return 'Your cart is empty.';
    }
    if (normalized == 'online' && cartService.totalAmount < _stripeMinimumPkr) {
      return 'Online payment needs at least ${formatPkr(_stripeMinimumPkr)}. Please choose cash on delivery.';
    }
    if (mounted &&
        bridge.paymentMethodDialogVisible &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    bridge.voiceExpectingCheckoutPayment = false;
    final ok = await _placeOrder(paymentMethod: normalized, silentToast: true);
    if (!ok) {
      return 'Could not place your order right now. Please try again.';
    }
    if (normalized == 'online') {
      return 'Online payment selected. I opened checkout and moved you to your orders.';
    }
    return 'Order placed with cash on delivery. I moved you to your orders.';
  }

  void _showPaymentMethodDialog() {
    final bridge = CustomerVoiceBridge.instance;
    bridge.paymentMethodDialogVisible = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => _PaymentMethodDialog(
        totalAmount: cartService.totalAmount,
        firestore: _firestore,
        onSelect: (method, {String? stripeCustomerId, String? savedCardId}) {
          Navigator.pop(ctx);
          bridge.voiceExpectingCheckoutPayment = false;
          _placeOrder(
            paymentMethod: method,
            stripeCustomerId: stripeCustomerId,
            savedCardId: savedCardId,
          );
        },
      ),
    ).whenComplete(() {
      bridge.paymentMethodDialogVisible = false;
      bridge.voiceExpectingCheckoutPayment = false;
    });
  }

  Future<bool> _placeOrder({
    required String paymentMethod,
    String? stripeCustomerId,
    String? savedCardId,
    bool silentToast = false,
  }) async {
    if (cartService.isEmpty) return false;

    setState(() => _placingOrder = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final customerName = userData['name'] ?? 'Customer';
      final customerPhone = userData['phone'] ?? '';
      final customerEmail = userData['email'] ?? user.email ?? '';
      final customerLat = (userData['lat'] as num?)?.toDouble();
      final customerLng = (userData['lng'] as num?)?.toDouble();
      final customerAddress = userData['address'] as String? ?? '';

      if (customerLat == null || customerLng == null) {
        if (!mounted) return false;
        setState(() => _placingOrder = false);
        if (!silentToast) {
          showAppToast(
            context,
            'Please set your delivery location in your profile first.',
          );
        }
        return false;
      }

      final initialStatus = paymentMethod == 'online'
          ? 'awaiting_payment'
          : 'pending';
      final paymentStatus = paymentMethod == 'cod' ? 'pending' : 'pending';

      for (var entry in cartService.cart.entries) {
        final restaurantId = entry.key;
        final items = entry.value;

        double restaurantTotal = 0;
        int totalQuantity = 0;
        List<Map<String, dynamic>> orderItems = [];

        for (var item in items) {
          final quantity = item['quantity'] ?? 1;
          final itemTotal = (item['price'] ?? 0) * quantity;
          final note = (item['note'] ?? '').toString().trim();
          restaurantTotal += itemTotal;
          totalQuantity += quantity as int;
          orderItems.add({
            'itemId': item['itemId'],
            'name': item['name'],
            'price': item['price'],
            'quantity': quantity,
            'itemTotal': itemTotal,
            'note': note,
          });
        }

        final restaurantDoc = await _firestore
            .collection('restaurants')
            .doc(restaurantId)
            .get();
        final connectedAccountId =
            restaurantDoc.data()?['stripeConnectId'] as String?;

        final customerOrderRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('orders')
            .doc();

        final effectivePaymentMethod = paymentMethod == 'saved_card'
            ? 'online'
            : paymentMethod;

        final restaurantOrderRef = await _firestore
            .collection('restaurants')
            .doc(restaurantId)
            .collection('orders')
            .add({
              'customerId': user.uid,
              'customerOrderId': customerOrderRef.id,
              'customerName': customerName,
              'customerPhone': customerPhone,
              'customerEmail': customerEmail,
              'customerLat': customerLat,
              'customerLng': customerLng,
              'customerAddress': customerAddress,
              'items': orderItems,
              'itemCount': totalQuantity,
              'total': restaurantTotal,
              'status': initialStatus,
              'paymentMethod': effectivePaymentMethod,
              'paymentStatus': paymentStatus,
              'createdAt': FieldValue.serverTimestamp(),
            });

        await customerOrderRef.set({
          'restaurantId': restaurantId,
          'restaurantOrderId': restaurantOrderRef.id,
          'restaurantName': items.first['restaurantName'] ?? 'Restaurant',
          'items': orderItems,
          'itemCount': totalQuantity,
          'total': restaurantTotal,
          'status': initialStatus,
          'paymentMethod': effectivePaymentMethod,
          'paymentStatus': paymentStatus,
          'createdAt': FieldValue.serverTimestamp(),
        });

        final debtDoc = await _firestore
            .collection('platformDebts')
            .doc(restaurantId)
            .get();
        final currentDebtPkr =
            (debtDoc.data()?['amount'] as num?)?.toDouble() ?? 0.0;
        final currentDebtPaisa = (currentDebtPkr * 100).round();

        if (paymentMethod == 'cod') {
          final codFee = restaurantTotal * 0.05;
          await _firestore.collection('platformDebts').doc(restaurantId).set({
            'amount': FieldValue.increment(codFee),
          }, SetOptions(merge: true));
        }

        if (paymentMethod == 'online') {
          final customerId =
              stripeCustomerId ??
              await PaymentService.ensureStripeCustomer(
                userId: user.uid,
                email: customerEmail,
                name: customerName,
              );

          if (connectedAccountId != null) {
            final payResult = await PaymentService.openConnectedCheckout(
              stripeCustomerId: customerId,
              items: orderItems,
              orderId: customerOrderRef.id,
              connectedAccountId: connectedAccountId,
              platformDebtPaisa: currentDebtPaisa,
            );

            if (payResult == null || payResult.sessionId == null) {
              await restaurantOrderRef.delete();
              await customerOrderRef.delete();
              if (mounted) {
                if (!silentToast) {
                  showAppToast(
                    context,
                    'Payment setup failed. Total may be too low for online payment. Try Cash on Delivery.',
                  );
                }
              }
              setState(() => _placingOrder = false);
              return false;
            }

            if (payResult.debtRecoveredPaisa > 0) {
              await _firestore
                  .collection('platformDebts')
                  .doc(restaurantId)
                  .set({
                    'amount': FieldValue.increment(-payResult.debtRecoveredPkr),
                  }, SetOptions(merge: true));
            }

            await _saveTransaction(
              customerId: user.uid,
              customerName: customerName,
              restaurantId: restaurantId,
              restaurantName: items.first['restaurantName'] ?? 'Restaurant',
              orderId: customerOrderRef.id,
              amount: restaurantTotal,
              platformFee: payResult.normalFeePkr,
              restaurantAmount: payResult.restaurantAmountPkr,
              paymentMethod: 'online',
              debtRecovered: payResult.debtRecoveredPkr,
              debtRemaining: currentDebtPkr - payResult.debtRecoveredPkr,
            );
          } else {
            final sessionId = await PaymentService.openCheckout(
              stripeCustomerId: customerId,
              items: orderItems,
              orderId: customerOrderRef.id,
            );

            if (sessionId == null) {
              await restaurantOrderRef.delete();
              await customerOrderRef.delete();
              if (mounted) {
                if (!silentToast) {
                  showAppToast(
                    context,
                    'Payment setup failed. Total may be too low for online payment. Try Cash on Delivery.',
                  );
                }
              }
              setState(() => _placingOrder = false);
              return false;
            }

            final platformFee = restaurantTotal * 0.05;
            await _saveTransaction(
              customerId: user.uid,
              customerName: customerName,
              restaurantId: restaurantId,
              restaurantName: items.first['restaurantName'] ?? 'Restaurant',
              orderId: customerOrderRef.id,
              amount: restaurantTotal,
              platformFee: platformFee,
              restaurantAmount: restaurantTotal - platformFee,
              paymentMethod: 'online',
            );
          }
        }

        if (paymentMethod == 'saved_card' && savedCardId != null) {
          if (connectedAccountId != null) {
            final payResult = await PaymentService.chargeWithSavedCardConnected(
              stripeCustomerId: stripeCustomerId!,
              paymentMethodId: savedCardId,
              amount: restaurantTotal,
              orderId: customerOrderRef.id,
              connectedAccountId: connectedAccountId,
              platformDebtPaisa: currentDebtPaisa,
            );

            if (payResult.success) {
              await restaurantOrderRef.update({
                'paymentStatus': 'paid',
                'status': 'pending',
              });
              await customerOrderRef.update({
                'paymentStatus': 'paid',
                'status': 'pending',
              });

              if (payResult.debtRecoveredPaisa > 0) {
                await _firestore
                    .collection('platformDebts')
                    .doc(restaurantId)
                    .set({
                      'amount': FieldValue.increment(
                        -payResult.debtRecoveredPkr,
                      ),
                    }, SetOptions(merge: true));
              }

              await _saveTransaction(
                customerId: user.uid,
                customerName: customerName,
                restaurantId: restaurantId,
                restaurantName: items.first['restaurantName'] ?? 'Restaurant',
                orderId: customerOrderRef.id,
                amount: restaurantTotal,
                platformFee: payResult.normalFeePkr,
                restaurantAmount: payResult.restaurantAmountPkr,
                paymentMethod: 'saved_card',
                debtRecovered: payResult.debtRecoveredPkr,
                debtRemaining: currentDebtPkr - payResult.debtRecoveredPkr,
              );
            } else {
              if (mounted) {
                if (!silentToast) {
                  showAppToast(
                    context,
                    'Card payment failed. Please try another method.',
                  );
                }
              }
              setState(() => _placingOrder = false);
              return false;
            }
          } else {
            final charged = await PaymentService.chargeWithSavedCard(
              stripeCustomerId: stripeCustomerId!,
              paymentMethodId: savedCardId,
              amount: restaurantTotal,
              orderId: customerOrderRef.id,
            );

            if (charged) {
              await restaurantOrderRef.update({
                'paymentStatus': 'paid',
                'status': 'pending',
              });
              await customerOrderRef.update({
                'paymentStatus': 'paid',
                'status': 'pending',
              });

              final platformFee = restaurantTotal * 0.05;
              await _saveTransaction(
                customerId: user.uid,
                customerName: customerName,
                restaurantId: restaurantId,
                restaurantName: items.first['restaurantName'] ?? 'Restaurant',
                orderId: customerOrderRef.id,
                amount: restaurantTotal,
                platformFee: platformFee,
                restaurantAmount: restaurantTotal - platformFee,
                paymentMethod: 'saved_card',
              );
            } else {
              if (mounted) {
                if (!silentToast) {
                  showAppToast(
                    context,
                    'Card payment failed. Please try another method.',
                  );
                }
              }
              setState(() => _placingOrder = false);
              return false;
            }
          }
        }

        try {
          await NotificationService.createNotification(
            userId: restaurantId,
            title: 'New order',
            message:
                '$customerName placed an order (${formatPkr(restaurantTotal)}, $totalQuantity items).',
            orderId: restaurantOrderRef.id,
          );
        } catch (e, st) {
          debugPrint('[CartView] Restaurant notification: $e\n$st');
        }
      }

      setState(() => cartService.clearCart());

      if (!mounted) return false;

      if (paymentMethod == 'online') {
        if (!silentToast) {
          showAppToast(context, 'Complete payment in the opened page');
        }
      } else if (paymentMethod == 'saved_card') {
        if (!silentToast) {
          showAppToast(context, 'Payment successful! Order placed.');
        }
      } else {
        if (!silentToast) {
          showAppToast(context, 'Order placed successfully!');
        }
      }
      if (!widget.embedded) Navigator.pop(context);
      return true;
    } catch (_) {
      if (!mounted) return false;
      if (!silentToast) {
        showAppToast(context, 'Something went wrong. Please try again later.');
      }
      return false;
    }
  }

  void _clearCart() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cart?'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Remove all items from your cart?'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlineButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Text('Cancel')],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => cartService.clearCart());
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.destructive,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Clear',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              if (!widget.embedded)
                GhostButton(
                  density: ButtonDensity.icon,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(RadixIcons.arrowLeft, size: 20),
                ),
              if (!widget.embedded) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cart').h4().semiBold(),
                    const Text(
                      'Review your items before ordering',
                    ).muted().small(),
                  ],
                ),
              ),
              if (cartService.isNotEmpty)
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: _clearCart,
                  child: Text(
                    'Clear',
                    style: TextStyle(color: theme.colorScheme.destructive),
                  ).small(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: cartService.isEmpty
              ? _buildEmptyCart(theme)
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: cartService.cart.entries.map((entry) {
                    final restaurantId = entry.key;
                    final items = entry.value;
                    final restaurantName = items.isNotEmpty
                        ? items.first['restaurantName'] ?? 'Restaurant'
                        : 'Restaurant';
                    return _buildRestaurantSection(
                      theme,
                      restaurantId,
                      restaurantName,
                      items,
                    );
                  }).toList(),
                ),
        ),
        if (cartService.isNotEmpty) _buildOrderSummary(theme),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(
      child: Container(
        color: theme.colorScheme.background,
        child: SafeArea(child: content),
      ),
    );
  }

  Widget _buildEmptyCart(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 64,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(height: 16),
          const Text('Your cart is empty').semiBold(),
          const SizedBox(height: 8),
          const Text('Add some delicious food!').muted().small(),
        ],
      ),
    );
  }

  Widget _buildRestaurantSection(
    ThemeData theme,
    String restaurantId,
    String restaurantName,
    List<Map<String, dynamic>> items,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    RadixIcons.home,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(restaurantName).semiBold(),
                ],
              ),
            ),
            const Divider(height: 1),
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildCartItem(theme, restaurantId, index, item);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(
    ThemeData theme,
    String restaurantId,
    int index,
    Map<String, dynamic> item,
  ) {
    final itemTotal = (item['price'] ?? 0) * (item['quantity'] ?? 1);
    final note = (item['note'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? 'Item').semiBold().small(),
                Text('${formatPkr(item['price'])} each').muted().small(),
                if (note.isNotEmpty)
                  Text('Customisation: $note').muted().xSmall(),
                const SizedBox(height: 6),
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: () =>
                      _editCustomizationNote(theme, restaurantId, index, item),
                  child: const Text('Edit customisation').xSmall(),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => _decreaseQuantity(restaurantId, index),
                child: Icon(
                  item['quantity'] > 1 ? RadixIcons.minus : RadixIcons.trash,
                  size: 14,
                  color: item['quantity'] > 1
                      ? theme.colorScheme.foreground
                      : theme.colorScheme.destructive,
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${item['quantity']}',
                  textAlign: TextAlign.center,
                ).semiBold().small(),
              ),
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => _increaseQuantity(restaurantId, index),
                child: const Icon(RadixIcons.plus, size: 14),
              ),
            ],
          ),
          SizedBox(
            width: 64,
            child: Text(
              formatPkr(itemTotal),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border(top: BorderSide(color: theme.colorScheme.border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total (${cartService.totalItems} items)').muted(),
              Text(
                formatPkr(cartService.totalAmount),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _placingOrder
                ? Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                : PrimaryButton(
                    onPressed: _showPaymentMethodDialog,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Text('Place Order')],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTransaction({
    required String customerId,
    required String customerName,
    required String restaurantId,
    required String restaurantName,
    required String orderId,
    required double amount,
    required double platformFee,
    required double restaurantAmount,
    required String paymentMethod,
    double debtRecovered = 0,
    double debtRemaining = 0,
  }) async {
    final txData = <String, dynamic>{
      'customerId': customerId,
      'customerName': customerName,
      'restaurantId': restaurantId,
      'restaurantName': restaurantName,
      'orderId': orderId,
      'amount': amount,
      'platformFee': platformFee,
      'restaurantAmount': restaurantAmount,
      'paymentMethod': paymentMethod,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (debtRecovered > 0) {
      txData['debtRecovered'] = debtRecovered;
      txData['debtRemaining'] = debtRemaining < 0 ? 0.0 : debtRemaining;
    }

    await _firestore.collection('transactions').add(txData);
  }
}

class _PaymentMethodDialog extends StatefulWidget {
  final double totalAmount;
  final FirebaseFirestore firestore;
  final void Function(
    String method, {
    String? stripeCustomerId,
    String? savedCardId,
  })
  onSelect;

  const _PaymentMethodDialog({
    required this.totalAmount,
    required this.firestore,
    required this.onSelect,
  });

  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  bool _loading = true;
  _SavedCardOption? _savedCard;

  /// Same controls as [CustomerShell] (shared [CustomerVoiceMicRow]).
  Widget _voiceMicRow(ThemeData theme, BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Or hold the microphone and say cash on delivery or online payment.',
        ).muted().small(),
        const SizedBox(height: 10),
        const Align(
          alignment: Alignment.centerRight,
          child: CustomerVoiceMicRow(),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await widget.firestore
          .collection('users')
          .doc(user.uid)
          .get();
      final customerId = doc.data()?['stripeCustomerId'] as String?;
      if (customerId != null && customerId.isNotEmpty) {
        final cards = await PaymentService.getSavedCards(
          stripeCustomerId: customerId,
        );
        if (cards.isNotEmpty) {
          _savedCard = _SavedCardOption(
            stripeCustomerId: customerId,
            card: cards.first,
          );
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final belowMinimum = widget.totalAmount < _CartViewState._stripeMinimumPkr;

    return AlertDialog(
      title: const Text('Payment Method'),
      content: SizedBox(
        width: 340,
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Loading payment options...').muted().small(),
                  _voiceMicRow(theme, context),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('How would you like to pay?').muted().small(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      onPressed: belowMinimum
                          ? null
                          : () => widget.onSelect('online'),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(RadixIcons.globe, size: 16),
                          SizedBox(width: 8),
                          Text('Pay Online'),
                        ],
                      ),
                    ),
                  ),
                  if (belowMinimum) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Online payment requires a minimum of ${formatPkr(_CartViewState._stripeMinimumPkr)}',
                      style: TextStyle(
                        color: theme.colorScheme.destructive,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlineButton(
                      onPressed: () => widget.onSelect('cod'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            RadixIcons.archive,
                            size: 16,
                            color: theme.colorScheme.foreground,
                          ),
                          const SizedBox(width: 8),
                          const Text('Cash on Delivery'),
                        ],
                      ),
                    ),
                  ),
                  if (_savedCard != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlineButton(
                        onPressed: belowMinimum
                            ? null
                            : () => widget.onSelect(
                                'saved_card',
                                stripeCustomerId: _savedCard!.stripeCustomerId,
                                savedCardId: _savedCard!.card.id,
                              ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              RadixIcons.cardStack,
                              size: 16,
                              color: theme.colorScheme.foreground,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_savedCard!.card.brand.toUpperCase()} ···· ${_savedCard!.card.last4}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  _voiceMicRow(theme, context),
                ],
              ),
      ),
    );
  }
}

class _SavedCardOption {
  final String stripeCustomerId;
  final SavedCard card;
  const _SavedCardOption({required this.stripeCustomerId, required this.card});
}

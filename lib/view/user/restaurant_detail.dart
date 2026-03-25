import 'package:flutter/material.dart' as material show Icon, Icons, IconButton;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/services/speech_service.dart';
import 'package:speak_dine/services/intent_service.dart';

class RestaurantDetailView extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;
  final VoidCallback? onCartChanged;
  final VoidCallback? onViewCart;
  final VoidCallback? onViewPayments;

  const RestaurantDetailView({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.onCartChanged,
    this.onViewCart,
    this.onViewPayments,
  });

  @override
  State<RestaurantDetailView> createState() => _RestaurantDetailViewState();
}

class _RestaurantDetailViewState extends State<RestaurantDetailView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SpeechService _speechService = SpeechService();
  final IntentService _intentService = IntentService();
  bool _isListening = false;
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    _speechService.init();
  }

  @override
  void dispose() {
    _speechService.dispose();
    super.dispose();
  }

  void _addToCart(Map<String, dynamic> item, String itemId) {
    setState(() {
      cartService.addItem(
          widget.restaurantId, widget.restaurantName, item, itemId);
    });
    widget.onCartChanged?.call();
    showAppToast(context, '${item['name']} added to cart');
  }

  Future<void> _handleVoiceCommand(String text) async {
    setState(() {
      _recognizedText = text;
      _isListening = false;
    });
    final intent = _intentService.detectIntent(text);
    bool stayedOnScreen = true;

    switch (intent.action) {
      case 'TELL_MENU':
        await _speakMenu();
        break;
      case 'ADD_TO_CART':
        await _addToCartByVoice(intent.itemName);
        break;
      case 'SHOW_CART':
        await _speechService.speak('Opening cart');
        widget.onViewCart?.call();
        stayedOnScreen = false;
        break;
      case 'PLACE_ORDER':
        await _speechService.speak('Opening cart to place order');
        widget.onViewCart?.call();
        stayedOnScreen = false;
        break;
      case 'MAKE_PAYMENT':
        await _speechService.speak('Opening payments');
        widget.onViewPayments?.call();
        stayedOnScreen = false;
        break;
      default:
        await _speechService.speak('Sorry, I did not understand. Say what is in the menu, or say the item name to add to cart.');
    }

    if (stayedOnScreen && mounted) _restartListeningAfterDelay();
  }

  void _restartListeningAfterDelay() {
    Future.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      final started = await _speechService.startListening(
        onResultText: (text, isFinal) {
          if (isFinal && text.trim().isNotEmpty) {
            _handleVoiceCommand(text);
          } else {
            setState(() => _recognizedText = text);
          }
        },
      );
      if (started && mounted) setState(() => _isListening = true);
    });
  }

  Future<void> _speakMenu() async {
    final snapshot = await _firestore
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menu')
        .get();
    if (!mounted) return;
    final docs = snapshot.docs;
    if (docs.isEmpty) {
      await _speechService.speak('No items in menu yet.');
      return;
    }
    final buffer = StringBuffer('${widget.restaurantName} menu. ');
    for (final doc in docs) {
      final d = doc.data();
      final name = d['name'] as String? ?? 'Item';
      final price = d['price'];
      final p = price is num ? price.toDouble() : 0.0;
      buffer.write('$name, ${p.toStringAsFixed(0)} rupees. ');
    }
    await _speechService.speak(buffer.toString());
  }

  Future<void> _addToCartByVoice(String? itemName) async {
    final snapshot = await _firestore
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menu')
        .get();
    if (!mounted) return;
    final docs = snapshot.docs;
    if (docs.isEmpty) {
      await _speechService.speak('Menu is empty.');
      return;
    }
    if (itemName == null || itemName.trim().isEmpty) {
      await _speechService.speak('Say the item name to add to cart. For example, chicken burger.');
      return;
    }
    final search = itemName.toLowerCase().trim();
    QueryDocumentSnapshot? match;
    for (final doc in docs) {
      final d = doc.data();
      final name = (d['name'] as String? ?? '').toLowerCase();
      if (name.contains(search) || search.contains(name)) {
        match = doc;
        break;
      }
    }
    if (match == null) {
      await _speechService.speak('Item not found. Say what is in the menu to hear the list.');
      return;
    }
    final item = match.data() as Map<String, dynamic>;
    _addToCart(item, match.id);
    await _speechService.speak('${item['name']} added to cart.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => Navigator.pop(context),
                child: Icon(RadixIcons.arrowLeft,
                    size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.restaurantName).semiBold(),
              ),
              material.IconButton(
                icon: material.Icon(
                  _isListening ? material.Icons.mic : material.Icons.mic_none,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                  onPressed: () async {
                    if (_isListening) {
                      await _speechService.stopListening();
                      setState(() => _isListening = false);
                    } else {
                      final started = await _speechService.startListening(
                        onResultText: (text, isFinal) {
                          if (isFinal && text.trim().isNotEmpty) {
                            _handleVoiceCommand(text);
                          } else {
                            setState(() => _recognizedText = text);
                          }
                        },
                      );
                      if (started) {
                        setState(() => _isListening = true);
                      }
                    }
                  },
              ),
              if (widget.onViewCart != null)
                GhostButton(
                  density: ButtonDensity.icon,
                  onPressed: widget.onViewCart,
                  child: _buildCartIcon(theme),
                ),
            ],
          ),
        ),
        if (_recognizedText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('You said: $_recognizedText', style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground)),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child:
              const Text('Browse the menu and add items to your cart')
                  .muted()
                  .small(),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Text('Menu').semiBold(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('restaurants')
                .doc(widget.restaurantId)
                .collection('menu')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildMenuSkeleton();
              }
              if (snapshot.hasError) {
                debugPrint(
                    '[RestaurantDetail] Menu stream error: ${snapshot.error}');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    showAppToast(
                        context, 'Unable to load menu. Please try again.');
                  }
                });
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(RadixIcons.crossCircled,
                          size: 48, color: theme.colorScheme.destructive),
                      const SizedBox(height: 16),
                      const Text('Unable to load menu').semiBold(),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(RadixIcons.reader,
                          size: 48,
                          color: theme.colorScheme.mutedForeground),
                      const SizedBox(height: 16),
                      const Text('No menu items available').muted(),
                    ],
                  ),
                );
              }
              final items = snapshot.data!.docs;
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  ...items.map((doc) {
                    final item = doc.data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildMenuItem(theme, item, doc.id),
                    );
                  }),
                  const SizedBox(height: 24),
                  _buildReviewsSection(theme),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsSection(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final reviews = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),
            const Text('Reviews').semiBold(),
            const SizedBox(height: 12),
            ...reviews.map((doc) {
              final review = doc.data() as Map<String, dynamic>;
              return _buildReviewCard(theme, review);
            }),
          ],
        );
      },
    );
  }

  Widget _buildReviewCard(ThemeData theme, Map<String, dynamic> review) {
    final rating = review['rating'] as int? ?? 0;
    final comment = review['comment'] as String? ?? '';
    final customerName = review['customerName'] as String? ?? 'Customer';
    final createdAt = review['createdAt'] as Timestamp?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(customerName).semiBold().small()),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) => Icon(
                    RadixIcons.star,
                    size: 14,
                    color: i < rating
                        ? theme.colorScheme.primary
                        : theme.colorScheme.muted,
                  )),
                ),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(comment).muted().small(),
            ],
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatTimeAgo(createdAt.toDate()),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Widget _buildMenuSkeleton() {
    return Skeletonizer(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: List.generate(
          5,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Bone.text(words: 2),
                        const SizedBox(height: 8),
                        const Bone.text(words: 5, fontSize: 12),
                        const SizedBox(height: 8),
                        const Bone.text(words: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Bone(
                      width: 56,
                      height: 32,
                      borderRadius:
                          BorderRadius.all(Radius.circular(8))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartIcon(ThemeData theme) {
    final count = cartService.totalItems;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(RadixIcons.archive, size: 20, color: theme.colorScheme.primary),
        if (count > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.destructive,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: theme.colorScheme.background,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMenuItem(
    ThemeData theme,
    Map<String, dynamic> item,
    String itemId,
  ) {
    final quantityInCart =
        cartService.getItemQuantity(widget.restaurantId, itemId);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 48,
              height: 48,
              child: item['imageUrl'] != null && item['imageUrl'].toString().isNotEmpty
                  ? Image.network(
                      item['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        child: Icon(RadixIcons.reader,
                            size: 18, color: theme.colorScheme.primary),
                      ),
                    )
                  : Container(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      child: Icon(RadixIcons.reader,
                          size: 18, color: theme.colorScheme.primary),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? 'Item').semiBold(),
                if (item['description'] != null &&
                    item['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item['description'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ).muted().small(),
                ],
                const SizedBox(height: 2),
                Text(
                  '${item['price']?.toStringAsFixed(2) ?? '0.00'} PKR',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              if (quantityInCart > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'x$quantityInCart',
                      style: TextStyle(
                        color: theme.colorScheme.primaryForeground,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () => _addToCart(item, itemId),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(RadixIcons.plus,
                      size: 18, color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

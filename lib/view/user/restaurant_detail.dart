import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' as material
    show AlwaysScrollableScrollPhysics, MaterialPageRoute, RefreshIndicator, SingleChildScrollView;
import 'package:skeletonizer/skeletonizer.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/utils/pkr_format.dart';
import 'package:speak_dine/widgets/menu_item_network_image.dart';
import 'package:speak_dine/constants/menu_dish_category.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:intl/intl.dart';

enum _MenuVoiceFactKind { price, description }

class RestaurantDetailView extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;
  final VoidCallback? onCartChanged;
  final VoidCallback? onViewCart;

  const RestaurantDetailView({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.onCartChanged,
    this.onViewCart,
  });

  @override
  State<RestaurantDetailView> createState() => _RestaurantDetailViewState();
}

class _RestaurantDetailViewState extends State<RestaurantDetailView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _menuStream;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestMenuDocs = [];

  /// Filled from Firestore for the header above reviews (replaces static "Menu" label).
  String? _restaurantCategoryLabel;
  String? _restaurantDescription;

  /// One auto voice intro per visit (description + reviews question).
  bool _scheduledRestaurantVoiceIntro = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _voiceRestaurantDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _voiceReviewsSub;

  late final Future<String?> Function() _voiceConfirmAddClosure =
      _confirmVoiceAddToCartFromMenu;

  @override
  void initState() {
    super.initState();
    _menuStream = _menuQuery.snapshots();
    final b = CustomerVoiceBridge.instance;
    b.confirmVoiceAddToCartFromMenu = _voiceConfirmAddClosure;
    b.speakableMenuItemsForVoice = _speakableMenuItemsForVoice;
    b.answerMenuItemVoiceFact = _answerMenuItemVoiceFact;
    b.restaurantVoiceMenuIntroShown = false;
    b.restaurantVoiceDetailDisplayName = widget.restaurantName;
    b.restaurantMenuIntroSpeech =
        "You're now in ${widget.restaurantName}. "
        'Would you like to hear the latest reviews?';
    _attachVoiceRestaurantContext();
  }

  void _scheduleRestaurantVoiceIntroOnce() {
    if (_scheduledRestaurantVoiceIntro || !mounted) {
      return;
    }
    final play = CustomerVoiceBridge.instance.playRestaurantDetailVoiceIntro;
    if (play == null) {
      return;
    }
    _scheduledRestaurantVoiceIntro = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(play());
    });
  }

  void _attachVoiceRestaurantContext() {
    final b = CustomerVoiceBridge.instance;
    _voiceRestaurantDocSub = _firestore
        .collection('restaurants')
        .doc(widget.restaurantId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (!snap.exists || snap.data() == null) {
        b.restaurantVoiceProfileSummary = null;
        b.restaurantVoiceCategoryPlain = null;
        b.restaurantVoiceDescriptionPlain = null;
        b.restaurantMenuIntroSpeech =
            "You're now in ${widget.restaurantName}. "
            'Would you like to hear the latest reviews?';
        setState(() {
          _restaurantCategoryLabel = null;
          _restaurantDescription = null;
        });
        return;
      }
      final m = snap.data()!;
      final desc = (m['description'] ?? '').toString().trim();
      final catId = m['restaurantCategory'] as String?;
      final catLabel = sdLibRestaurantCategoryLabel(catId);
      final catDisplay =
          (catLabel != null && catLabel.isNotEmpty) ? catLabel : null;
      final descDisplay = desc.isNotEmpty ? desc : null;
      setState(() {
        _restaurantCategoryLabel = catDisplay;
        _restaurantDescription = descDisplay;
      });
      final parts = <String>[
        'You are in restaurant "${widget.restaurantName}".',
        if (catDisplay != null) 'Category: $catDisplay.',
        if (descDisplay != null) 'Description: $descDisplay.',
      ];
      b.restaurantVoiceProfileSummary = parts.join(' ');

      final introParts = <String>[
        "You're now in ${widget.restaurantName}.",
        if (catDisplay != null) 'The category is $catDisplay.',
        if (descDisplay != null) 'Description: $descDisplay.',
      ];
      b.restaurantMenuIntroSpeech =
          '${introParts.join(' ')} Would you like to hear the latest reviews?';
      b.restaurantVoiceCategoryPlain = catDisplay;
      b.restaurantVoiceDescriptionPlain = descDisplay;
      _scheduleRestaurantVoiceIntroOnce();
    });

    _voiceReviewsSub = _firestore
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(3)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (snap.docs.isEmpty) {
        b.restaurantVoiceReviewsSummary =
            'No reviews yet for ${widget.restaurantName}.';
        return;
      }
      b.restaurantVoiceReviewsSummary = _voiceFormatReviews(snap.docs);
    });
  }

  String _voiceFormatReviews(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final buf = StringBuffer();
    for (var i = 0; i < docs.length; i++) {
      final r = docs[i].data();
      final rawRating = r['rating'];
      final rating = rawRating is num
          ? rawRating.round().clamp(0, 5)
          : int.tryParse('$rawRating') ?? 0;
      final comment = (r['comment'] as String? ?? '').trim();
      buf.write('Review ${i + 1}. ');
      buf.write('$rating out of 5 stars.');
      if (comment.isNotEmpty) {
        buf.write(' $comment');
      }
      if (i < docs.length - 1) {
        buf.write(' ');
      }
    }
    return buf.toString().trim();
  }

  @override
  void didUpdateWidget(RestaurantDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId) {
      _voiceRestaurantDocSub?.cancel();
      _voiceReviewsSub?.cancel();
      _menuStream = _menuQuery.snapshots();
      _latestMenuDocs = [];
      _scheduledRestaurantVoiceIntro = false;
      CustomerVoiceBridge.instance.restaurantVoiceDetailDisplayName =
          widget.restaurantName;
      _attachVoiceRestaurantContext();
    }
  }

  @override
  void dispose() {
    final b = CustomerVoiceBridge.instance;
    if (b.confirmVoiceAddToCartFromMenu == _voiceConfirmAddClosure) {
      b.confirmVoiceAddToCartFromMenu = null;
    }
    if (b.speakableMenuItemsForVoice == _speakableMenuItemsForVoice) {
      b.speakableMenuItemsForVoice = null;
    }
    if (b.answerMenuItemVoiceFact == _answerMenuItemVoiceFact) {
      b.answerMenuItemVoiceFact = null;
    }
    b.restaurantMenuVoiceSummary = null;
    b.restaurantVoiceProfileSummary = null;
    b.restaurantVoiceReviewsSummary = null;
    b.restaurantMenuIntroSpeech = null;
    b.restaurantVoiceMenuIntroShown = false;
    b.voiceAwaitingRestaurantReviewsYesNo = false;
    b.restaurantVoiceDetailDisplayName = null;
    b.restaurantVoiceCategoryPlain = null;
    b.restaurantVoiceDescriptionPlain = null;
    _voiceRestaurantDocSub?.cancel();
    _voiceReviewsSub?.cancel();
    super.dispose();
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _groupMenuDocsForVoice(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped = {
      for (final id in MenuDishCategory.idsInMenuOrder)
        id: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    };
    for (final doc in docs) {
      final cat = MenuDishCategory.normalizeId(doc.data()['dishCategory']);
      grouped[cat]!.add(doc);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final na = (a.data()['name'] ?? '').toString().toLowerCase();
        final nb = (b.data()['name'] ?? '').toString().toLowerCase();
        return na.compareTo(nb);
      });
    }
    return grouped;
  }

  String? _speakableMenuItemsForVoice({String? categoryKey}) {
    if (_latestMenuDocs.isEmpty) {
      return 'The menu is still loading. Try again in a moment.';
    }
    const maxItems = 24;
    final grouped = _groupMenuDocsForVoice(_latestMenuDocs);

    String formatSection(
      String heading,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) {
      if (docs.isEmpty) {
        return '';
      }
      final slice =
          docs.length > maxItems ? docs.sublist(0, maxItems) : docs;
      final parts = slice.map((doc) {
        final data = doc.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          return null;
        }
        final desc = (data['description'] ?? '').toString().trim();
        return desc.isNotEmpty ? '$name: $desc' : name;
      }).whereType<String>();
      final buf = StringBuffer('Here are the $heading. ');
      buf.write(parts.join('. '));
      buf.write('.');
      if (docs.length > maxItems) {
        buf.write(' More items are on the screen.');
      }
      return buf.toString();
    }

    if (categoryKey != null) {
      if (!MenuDishCategory.idsInMenuOrder.contains(categoryKey)) {
        return null;
      }
      final docs = grouped[categoryKey]!;
      if (docs.isEmpty) {
        return 'There are no ${MenuDishCategory.sectionHeadingFor(categoryKey).toLowerCase()} on this menu yet.';
      }
      return formatSection(
        MenuDishCategory.sectionHeadingFor(categoryKey),
        docs,
      );
    }

    final sections = <String>[];
    for (final id in MenuDishCategory.idsInMenuOrder) {
      final docs = grouped[id]!;
      if (docs.isEmpty) {
        continue;
      }
      sections.add(formatSection(MenuDishCategory.sectionHeadingFor(id), docs));
    }
    if (sections.isEmpty) {
      return 'This menu has no items yet.';
    }
    return sections.join(' ');
  }

  String _voiceMenuSummaryFromGrouped(
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> grouped,
  ) {
    final buf = StringBuffer(
      'Restaurant "${widget.restaurantName}" menu snapshot:\n',
    );
    var sections = 0;
    for (final catId in MenuDishCategory.idsInMenuOrder) {
      if (sections >= 6) {
        break;
      }
      final sectionDocs = grouped[catId]!;
      if (sectionDocs.isEmpty) {
        continue;
      }
      final heading = MenuDishCategory.sectionHeadingFor(catId);
      final names = sectionDocs
          .take(5)
          .map((d) => (d.data()['name'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
      if (names.isEmpty) {
        continue;
      }
      buf.writeln('$heading — examples: $names.');
      sections++;
    }
    buf.writeln(
      '\nAll menu items (authoritative for price and description; read prices exactly as shown):',
    );
    for (final catId in MenuDishCategory.idsInMenuOrder) {
      final sectionDocs = grouped[catId]!;
      if (sectionDocs.isEmpty) {
        continue;
      }
      buf.writeln('[${MenuDishCategory.sectionHeadingFor(catId)}]');
      for (final d in sectionDocs) {
        final data = d.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          continue;
        }
        final desc = (data['description'] ?? '').toString().trim();
        buf.write('- $name · ${formatPkr(data['price'])}');
        if (desc.isNotEmpty) {
          buf.write(' · $desc');
        }
        buf.writeln();
      }
    }
    return buf.toString().trim();
  }

  String? _answerMenuItemVoiceFact(String utterance) {
    if (_latestMenuDocs.isEmpty) {
      return null;
    }
    final lower = utterance.toLowerCase().trim();
    final kind = _voiceDetectMenuFactKind(lower);
    if (kind == null) {
      return null;
    }
    final fragment = _voiceExtractMenuItemFragment(lower);
    if (fragment == null || fragment.trim().length < 2) {
      return 'Which dish? Say the item name together with price or description.';
    }
    if (RegExp(
      r'\b(reviews?|ratings?|restaurant|the\s+menu|this\s+place)\b',
    ).hasMatch(fragment)) {
      return null;
    }
    if (_voiceFragmentIsMenuSectionOnly(fragment)) {
      return null;
    }
    final doc = _voiceBestMenuDocMatch(fragment);
    if (doc == null) {
      return 'I could not find that dish on this menu. Say the name as listed, or tap the item.';
    }
    final data = doc.data();
    final name = (data['name'] ?? 'That item').toString().trim();
    if (name.isEmpty) {
      return null;
    }
    if (kind == _MenuVoiceFactKind.price) {
      return '$name is ${formatPkr(data['price'])}.';
    }
    final desc = (data['description'] ?? '').toString().trim();
    if (desc.isEmpty) {
      return '$name does not have a description on this menu.';
    }
    return '$name: $desc';
  }

  _MenuVoiceFactKind? _voiceDetectMenuFactKind(String lower) {
    final priceHits = [
      RegExp(r'\bhow\s+much\b'),
      RegExp(r'\bprice\b'),
      RegExp(r'\bprize\b'), // common STT mishear for "price"
      RegExp(r'\bcost\b'),
      RegExp(r'\bpricing\b'),
      RegExp(r'\brate\b'),
      RegExp(r'\brupees?\b'),
      RegExp(r'\brs\.?\b'),
      RegExp(r'\bpkr\b'),
    ].where((r) => r.hasMatch(lower)).length;
    final descHits = [
      RegExp(r'\bdescription\b'),
      RegExp(r'\bdiscription\b'),
      RegExp(r'\bdescribe\b'),
      RegExp(r'\bdetails?\b'),
      RegExp(r'\bingredients?\b'),
      RegExp(r"what's\s+in\b"),
      RegExp(r'\bwhats\s+in\b'),
      RegExp(r'\btell\s+me\s+about\b'),
      RegExp(r'\binfo\s+on\b'),
    ].where((r) => r.hasMatch(lower)).length;
    if (priceHits == 0 && descHits == 0) {
      return null;
    }
    if (priceHits >= descHits) {
      return _MenuVoiceFactKind.price;
    }
    return _MenuVoiceFactKind.description;
  }

  String? _voiceExtractMenuItemFragment(String lower) {
    final patterns = <RegExp>[
      RegExp(r'^how\s+much\s+(?:is|for|does)\s+(?:the\s+)?(.+)$'),
      RegExp(r"^what(?:'s|s| is)\s+the\s+(?:price|cost)\s+(?:of|for)\s+(.+)$"),
      RegExp(r'^what(?:\s+is)?\s+(?:the\s+)?(?:price|cost)\s+(?:of|for)\s+(.+)$'),
      RegExp(r"^(?:what(?:'s|s| is)|tell\s+me)\s+(?:the\s+)?price\s+(?:of|for)\s+(.+)$"),
      RegExp(
        r'^(.+?)\s+(?:price|cost|pricing|prize)\s*(?:please|thanks|thank you)?\s*$',
      ),
      RegExp(r'^(?:price|cost|pricing|prize)\s+(?:of|for)\s+(.+)$'),
      RegExp(r'^(?:price|cost|pricing|prize)\s+for\s+(.+)$'),
      RegExp(
        r'^(?:describe|description|discription|details?)\s+(?:the\s+)?(?:item\s+)?(.+)$',
      ),
      RegExp(r'^(.+?)\s+(?:description|discription|details?)\s*$'),
      RegExp(r'^tell\s+me\s+about\s+(.+)$'),
      RegExp(r'^info\s+on\s+(.+)$'),
      RegExp(r"^what(?:'s|s| is)\s+in\s+(?:the\s+)?(.+)$"),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(lower);
      if (m != null && m.groupCount >= 1) {
        final g = m.group(1)?.trim();
        if (g != null && g.isNotEmpty) {
          return g;
        }
      }
    }
    final stripped = lower
        .replaceAll(
          RegExp(
            r'\b(how\s+much|price|prize|cost|pricing|rate|rs\.?|pkr|rupees?|description|discription|describe|details?|ingredients?|tell\s+me\s+about|info\s+on|whats\s+in)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r"\bwhat's\s+in\b"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.isEmpty ? null : stripped;
  }

  bool _voiceFragmentIsMenuSectionOnly(String fragment) {
    final f = fragment.toLowerCase().trim();
    const sections = {
      'appetizer',
      'appetisers',
      'appetizers',
      'starter',
      'starters',
      'first course',
      'main',
      'mains',
      'main course',
      'main courses',
      'entree',
      'entrees',
      'dessert',
      'desserts',
      'sweet',
      'sweets',
      'afters',
      'drink',
      'drinks',
      'beverage',
      'beverages',
    };
    return sections.contains(f);
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _voiceBestMenuDocMatch(
    String fragment,
  ) {
    final f = fragment.toLowerCase().trim();
    if (f.isEmpty) {
      return null;
    }
    final docs = _latestMenuDocs;
    for (final d in docs) {
      final name =
          (d.data()['name'] ?? '').toString().toLowerCase().trim();
      if (name.isNotEmpty && name == f) {
        return d;
      }
    }
    for (final d in docs) {
      final name =
          (d.data()['name'] ?? '').toString().toLowerCase().trim();
      if (name.isNotEmpty && name.contains(f)) {
        return d;
      }
    }
    for (final d in docs) {
      final name =
          (d.data()['name'] ?? '').toString().toLowerCase().trim();
      if (name.length >= 3 && f.contains(name)) {
        return d;
      }
    }
    final ftokens =
        f.split(RegExp(r'\s+')).where((t) => t.length > 1).toSet();
    if (ftokens.isEmpty) {
      return null;
    }
    QueryDocumentSnapshot<Map<String, dynamic>>? best;
    var bestScore = 0;
    for (final d in docs) {
      final name =
          (d.data()['name'] ?? '').toString().toLowerCase().trim();
      final ntokens =
          name.split(RegExp(r'\s+')).where((t) => t.length > 1).toSet();
      final overlap = ftokens.intersection(ntokens).length;
      if (overlap > bestScore) {
        bestScore = overlap;
        best = d;
      }
    }
    return bestScore > 0 ? best : null;
  }

  CollectionReference<Map<String, dynamic>> get _menuQuery => _firestore
      .collection('restaurants')
      .doc(widget.restaurantId)
      .collection('menu');

  /// Syncs persistence from server, then re-subscribes so deleted dishes disappear reliably.
  Future<void> _refreshMenuFromServer() async {
    await _menuQuery.get(const GetOptions(source: Source.server));
    if (!mounted) return;
    setState(() {
      _menuStream = _menuQuery.snapshots();
    });
  }

  void _addToCart(Map<String, dynamic> item, String itemId) {
    setState(() {
      cartService.addItem(
          widget.restaurantId, widget.restaurantName, item, itemId);
    });
    widget.onCartChanged?.call();
    showAppToast(context, '${item['name']} added to cart');
  }

  /// Voice: add [CustomerVoiceBridge.pendingVoiceCartItem] if it matches a menu line.
  Future<String?> _confirmVoiceAddToCartFromMenu() async {
    final bridge = CustomerVoiceBridge.instance;
    final needle = (bridge.pendingVoiceCartItem ?? '').toLowerCase().trim();
    if (needle.isEmpty) {
      return 'Say what to add first, for example add burger to cart.';
    }
    if (_latestMenuDocs.isEmpty) {
      return 'Menu is still loading. Try again in a second.';
    }
    QueryDocumentSnapshot<Map<String, dynamic>>? best;
    var bestScore = 0;
    for (final doc in _latestMenuDocs) {
      final name = (doc.data()['name'] ?? '').toString().toLowerCase();
      if (name.isEmpty) {
        continue;
      }
      var score = 0;
      if (name == needle) {
        score = 100;
      } else if (name.contains(needle) || needle.contains(name)) {
        score = 85;
      } else {
        for (final w in needle.split(RegExp(r'\s+')).where((e) => e.length > 2)) {
          if (name.contains(w)) {
            score = 75;
          }
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = doc;
      }
    }
    if (best == null || bestScore < 75) {
      return 'No menu item matched. Tap the plus button next to your dish.';
    }
    if (!mounted) {
      return 'Try again.';
    }
    _addToCart(best.data(), best.id);
    bridge.clearPendingVoiceCartItem();
    return null;
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
              if (widget.onViewCart != null)
                GhostButton(
                  density: ButtonDensity.icon,
                  onPressed: widget.onViewCart,
                  child: _buildCartIcon(theme),
                ),
            ],
          ),
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
          child: _buildRestaurantInfoHeader(theme),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _menuStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return _buildMenuSkeleton();
              }
              if (snapshot.hasError) {
                debugPrint(
                    '[RestaurantDetail] Menu stream error: ${snapshot.error}');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  CustomerVoiceBridge.instance.restaurantMenuVoiceSummary = null;
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  CustomerVoiceBridge.instance.restaurantMenuVoiceSummary = null;
                });
                return material.RefreshIndicator(
                  onRefresh: _refreshMenuFromServer,
                  child: SingleChildScrollView(
                    physics: const material.AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.45,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(RadixIcons.reader,
                                size: 48,
                                color: theme.colorScheme.mutedForeground),
                            const SizedBox(height: 16),
                            const Text('No menu items available').muted(),
                            const SizedBox(height: 8),
                            Text(
                              'Pull down to refresh',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                snapshot.data!.docs,
              );
              _latestMenuDocs = docs;
              final grouped = {
                for (final id in MenuDishCategory.idsInMenuOrder)
                  id: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              };
              for (final doc in docs) {
                final data = doc.data();
                final cat = MenuDishCategory.normalizeId(data['dishCategory']);
                grouped[cat]!.add(doc);
              }
              for (final list in grouped.values) {
                list.sort((a, b) {
                  final na =
                      (a.data()['name'] ?? '').toString().toLowerCase();
                  final nb =
                      (b.data()['name'] ?? '').toString().toLowerCase();
                  return na.compareTo(nb);
                });
              }
              CustomerVoiceBridge.instance.restaurantMenuVoiceSummary =
                  _voiceMenuSummaryFromGrouped(grouped);
              var isFirstSection = true;
              final sectionChildren = <Widget>[];
              for (final catId in MenuDishCategory.idsInMenuOrder) {
                final sectionDocs = grouped[catId]!;
                if (sectionDocs.isEmpty) continue;
                sectionChildren.add(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: isFirstSection ? 0 : 22,
                          bottom: 10,
                        ),
                        child: Text(
                          MenuDishCategory.sectionHeadingFor(catId),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      ...sectionDocs.map((doc) {
                        final item = doc.data();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildMenuItem(context, theme, item, doc.id),
                        );
                      }),
                    ],
                  ),
                );
                isFirstSection = false;
              }
              return material.RefreshIndicator(
                onRefresh: _refreshMenuFromServer,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const material.AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildReviewsSection(theme),
                    const SizedBox(height: 20),
                    ...sectionChildren,
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRestaurantInfoHeader(ThemeData theme) {
    final cat = _restaurantCategoryLabel;
    final desc = _restaurantDescription;
    if ((cat == null || cat.isEmpty) && (desc == null || desc.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cat != null && cat.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              cat,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (desc != null && desc.isNotEmpty) ...[
          SizedBox(height: cat != null && cat.isNotEmpty ? 10 : 0),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Description: ').semiBold().small(),
              Expanded(
                child: Text(desc).muted().small(),
              ),
            ],
          ),
        ],
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
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final reviews = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reviews').semiBold(),
            const SizedBox(height: 12),
            SizedBox(
              height: 158,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: reviews.length + 1,
                itemBuilder: (context, index) {
                  if (index < reviews.length) {
                    final review = reviews[index].data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 268,
                        child: _buildReviewCard(theme, review),
                      ),
                    );
                  }
                  return _buildSeeAllReviewsButton(theme);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSeeAllReviewsButton(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Center(
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              material.MaterialPageRoute<void>(
                builder: (_) => RestaurantAllReviewsPage(
                  restaurantId: widget.restaurantId,
                ),
              ),
            );
          },
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                RadixIcons.chevronRight,
                size: 22,
                color: theme.colorScheme.primaryForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewCard(ThemeData theme, Map<String, dynamic> review) {
    final rating = review['rating'] as int? ?? 0;
    final comment = review['comment'] as String? ?? '';
    final createdAt = review['createdAt'] as Timestamp?;
    final customerId = (review['customerId'] ?? '').toString().trim();
    final baseName = _reviewerDisplayName(review);
    final baseImage = _reviewerImageUrl(review);
    final needsLookup =
        customerId.isNotEmpty && (baseName == 'Customer' || baseImage == null);

    Widget buildCardContent({
      required String name,
      required String? imageUrl,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildReviewerAvatar(
                          theme: theme,
                          imageUrl: imageUrl,
                          name: name,
                          size: 28,
                          fontSize: 11,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(name).semiBold().small()),
                      ],
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatReviewDateTime(createdAt.toDate()),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    RadixIcons.star,
                    size: 14,
                    color: i < rating
                        ? theme.colorScheme.primary
                        : theme.colorScheme.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              comment.isNotEmpty ? comment : 'No comment',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ).muted().small(),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.border.withValues(alpha: 0.35),
          ),
        ),
        child: needsLookup
            ? FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _firestore.collection('users').doc(customerId).get(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  final resolvedName = [
                    baseName,
                    data?['username']?.toString(),
                    data?['name']?.toString(),
                    data?['fullName']?.toString(),
                    data?['displayName']?.toString(),
                  ].map((e) => (e ?? '').trim()).firstWhere(
                        (s) => s.isNotEmpty && s != 'Customer',
                        orElse: () => baseName,
                      );
                  final resolvedImage = [
                    baseImage,
                    data?['profileImageUrl']?.toString(),
                    data?['photoUrl']?.toString(),
                    data?['avatarUrl']?.toString(),
                  ].map((e) => (e ?? '').trim()).firstWhere(
                        (s) => s.isNotEmpty,
                        orElse: () => '',
                      );
                  return buildCardContent(
                    name: resolvedName,
                    imageUrl: resolvedImage.isNotEmpty ? resolvedImage : null,
                  );
                },
              )
            : buildCardContent(name: baseName, imageUrl: baseImage),
      ),
    );
  }

  String _formatReviewDateTime(DateTime date) =>
      DateFormat('d MMM y · h:mm a').format(date);

  String _reviewerDisplayName(Map<String, dynamic> review) {
    for (final key in ['customerName', 'customerDisplayName', 'customerUsername']) {
      final value = review[key];
      if (value == null) continue;
      final s = value.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return 'Customer';
  }

  String? _reviewerImageUrl(Map<String, dynamic> review) {
    for (final key in ['customerProfileImageUrl', 'customerPhotoUrl', 'customerAvatarUrl']) {
      final value = review[key];
      if (value == null) continue;
      final s = value.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  Widget _buildReviewerAvatar({
    required ThemeData theme,
    required String? imageUrl,
    required String name,
    required double size,
    required double fontSize,
  }) {
    final initials = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'C';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: fontSize,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
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
    BuildContext context,
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
          menuItemImageOrPlaceholder(
            context: context,
            item: item,
            size: 48,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? 'Item').semiBold(),
                if (item['description'] != null &&
                    item['description'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item['description'].toString().trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ).muted().small(),
                ],
                const SizedBox(height: 8),
                Text(
                  formatPkr(item['price']),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
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

class RestaurantAllReviewsPage extends StatelessWidget {
  const RestaurantAllReviewsPage({
    super.key,
    required this.restaurantId,
  });

  final String restaurantId;

  String _formatReviewDateTime(DateTime date) =>
      DateFormat('d MMM y · h:mm a').format(date);

  String _reviewerDisplayName(Map<String, dynamic> review) {
    for (final key in ['customerName', 'customerDisplayName', 'customerUsername']) {
      final value = review[key];
      if (value == null) continue;
      final s = value.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return 'Customer';
  }

  String? _reviewerImageUrl(Map<String, dynamic> review) {
    for (final key in ['customerProfileImageUrl', 'customerPhotoUrl', 'customerAvatarUrl']) {
      final value = review[key];
      if (value == null) continue;
      final s = value.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  Widget _buildReviewerAvatar({
    required ThemeData theme,
    required String? imageUrl,
    required String name,
    required double size,
    required double fontSize,
  }) {
    final initials = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'C';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: fontSize,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
              child: Row(
                children: [
                  GhostButton(
                    density: ButtonDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(RadixIcons.arrowLeft, size: 18),
                  ),
                  const SizedBox(width: 4),
                  const Text('All reviews').h4().semiBold(),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: firestore
                    .collection('restaurants')
                    .doc(restaurantId)
                    .collection('reviews')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No reviews yet.',
                          style: TextStyle(
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ),
                    );
                  }
                  return material.SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      children: docs.map((doc) {
                        final review = doc.data() as Map<String, dynamic>;
                        final rating = review['rating'] as int? ?? 0;
                        final comment = review['comment'] as String? ?? '';
                        final customerName = _reviewerDisplayName(review);
                        final reviewerImage = _reviewerImageUrl(review);
                        final createdAt = review['createdAt'] as Timestamp?;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.border
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              _buildReviewerAvatar(
                                                theme: theme,
                                                imageUrl: reviewerImage,
                                                name: customerName,
                                                size: 32,
                                                fontSize: 12,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                  child:
                                                      Text(customerName).semiBold()),
                                            ],
                                          ),
                                          if (createdAt != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatReviewDateTime(
                                                  createdAt.toDate()),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme
                                                    .colorScheme.mutedForeground,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(
                                        5,
                                        (i) => Icon(
                                          RadixIcons.star,
                                          size: 16,
                                          color: i < rating
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  comment.isNotEmpty ? comment : 'No comment',
                                ).muted().small(),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

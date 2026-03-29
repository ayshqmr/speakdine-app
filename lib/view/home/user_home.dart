import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/widgets/notification_bell.dart';
import 'package:speak_dine/view/authScreens/login_view.dart';
import 'package:speak_dine/view/user/restaurant_detail.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/utils/restaurant_hours.dart';
import 'package:speak_dine/widgets/sd_lib_restaurant_search_filters.dart';
import 'package:speak_dine/utils/city_normalize.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';

class UserHomeView extends StatefulWidget {
  final VoidCallback? onCartChanged;
  final VoidCallback? onViewCart;

  const UserHomeView({super.key, this.onCartChanged, this.onViewCart});

  @override
  State<UserHomeView> createState() => _UserHomeViewState();
}

class _UserHomeViewState extends State<UserHomeView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  SdLibRestaurantExploreFilters _exploreFilters =
      const SdLibRestaurantExploreFilters();

  @override
  void initState() {
    super.initState();
    final bridge = CustomerVoiceBridge.instance;
    bridge.applySearchQuery = _voiceApplySearchQuery;
    bridge.applyCategoryId = _voiceApplyCategoryId;
    bridge.openRestaurantByName = _voiceOpenRestaurantByName;
  }

  @override
  void dispose() {
    final bridge = CustomerVoiceBridge.instance;
    if (bridge.applySearchQuery == _voiceApplySearchQuery) {
      bridge.applySearchQuery = null;
    }
    if (bridge.applyCategoryId == _voiceApplyCategoryId) {
      bridge.applyCategoryId = null;
    }
    if (bridge.openRestaurantByName == _voiceOpenRestaurantByName) {
      bridge.openRestaurantByName = null;
    }
    _searchController.dispose();
    super.dispose();
  }

  void _voiceApplySearchQuery(String query) {
    if (!mounted) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _voiceApplyCategoryId(String? categoryId) {
    if (!mounted) return;
    setState(() {
      _exploreFilters = SdLibRestaurantExploreFilters(
        categoryId: categoryId,
        openNowOnly: _exploreFilters.openNowOnly,
      );
    });
  }

  Future<bool> _voiceOpenRestaurantByName(String rawName) async {
    final nameNeedle = rawName.toLowerCase().trim();
    if (nameNeedle.isEmpty) return false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return false;

    final userSnap = await _firestore.collection('users').doc(user.uid).get();
    final userCityKey = normalizeCityKey(userSnap.data()?['city'] as String?);
    if (userCityKey == null) {
      if (mounted) {
        showAppToast(context, 'Set your city in Profile to find restaurants.');
      }
      return false;
    }

    final snap = await _firestore.collection('restaurants').get();
    String? bestId;
    String bestDisplayName = '';
    var bestScore = -1;

    for (final doc in snap.docs) {
      final data = doc.data();
      if (!restaurantCityMatchesUserExplore(userCityKey, data)) continue;
      final rName = (data['restaurantName'] ??
              data['name'] ??
              data['businessName'] ??
              '')
          .toString();
      final lower = rName.toLowerCase();
      var score = 0;
      if (lower == nameNeedle) {
        score = 100;
      } else if (lower.contains(nameNeedle)) {
        score = 80;
      } else if (nameNeedle.contains(lower.split(' ').first) &&
          lower.split(' ').first.length > 2) {
        score = 60;
      } else {
        final tokens = nameNeedle.split(RegExp(r'\s+'));
        for (final t in tokens) {
          if (t.length > 2 && lower.contains(t)) score = 70;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestId = doc.id;
        bestDisplayName = rName.isNotEmpty ? rName : 'Restaurant';
      }
    }

    if (bestId == null || bestScore < 60 || !mounted) {
      if (mounted) {
        showAppToast(context, 'No restaurant matched "$rawName".');
      }
      return false;
    }

    final id = bestId;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RestaurantDetailView(
          restaurantId: id,
          restaurantName: bestDisplayName,
          onCartChanged: () {
            if (!mounted) return;
            setState(() {});
            widget.onCartChanged?.call();
          },
          onViewCart: widget.onViewCart,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
      widget.onCartChanged?.call();
    }
    return true;
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnap) {
        final userWaiting =
            userSnap.connectionState == ConnectionState.waiting;
        final userData = userSnap.data?.data();
        final displayName = (userData?['name'] as String?)?.trim();
        final helloName =
            (displayName != null && displayName.isNotEmpty) ? displayName : 'Customer';
        final userCityKey = normalizeCityKey(userData?['city'] as String?);
        final cityDisplay = (userData?['city'] as String?)?.trim() ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hello, $helloName').h4().semiBold(),
                        const Text('What would you like to eat?')
                            .muted()
                            .small(),
                      ],
                    ),
                  ),
                  const NotificationBell(),
                  const SizedBox(width: 8),
                  GhostButton(
                    density: ButtonDensity.icon,
                    onPressed: _logout,
                    child: Icon(RadixIcons.exit,
                        size: 20, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ValueListenableBuilder<String>(
                valueListenable: CustomerVoiceBridge.instance.userSpeechLine,
                builder: (context, userText, _) {
                  return ValueListenableBuilder<String>(
                    valueListenable:
                        CustomerVoiceBridge.instance.assistantSpeechLine,
                    builder: (context, asstText, __) {
                      if (userText.isEmpty && asstText.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (userText.isNotEmpty) ...[
                                Text(
                                  'You',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.mutedForeground,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  userText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: theme.colorScheme.foreground,
                                  ),
                                ),
                              ],
                              if (userText.isNotEmpty && asstText.isNotEmpty)
                                const SizedBox(height: 10),
                              if (asstText.isNotEmpty) ...[
                                Text(
                                  'Assistant',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.mutedForeground,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  asstText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: theme.colorScheme.foreground,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: userCityKey != null
                  ? Text(
                      cityDisplay.isNotEmpty
                          ? 'Restaurants in $cityDisplay'
                          : 'Restaurants near you',
                    ).semiBold()
                  : const Text('Restaurants near you').semiBold(),
            ),
            const SizedBox(height: 10),
            if (userWaiting)
              Expanded(child: _buildRestaurantListSkeleton(theme))
            else if (userCityKey == null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          RadixIcons.pinTop,
                          size: 48,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        const SizedBox(height: 16),
                        const Text('Set your city').semiBold(),
                        const SizedBox(height: 8),
                        Text(
                          'Add your city in Profile so we can show restaurants in your area. It should match how restaurants list their city.',
                          textAlign: TextAlign.center,
                        ).muted().small(),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SdLibRestaurantSearchFilterBar(
                  controller: _searchController,
                  theme: theme,
                  onOpenFilters: () async {
                    final result = await showSdLibRestaurantFilterSheet(
                      context,
                      theme: theme,
                      initial: _exploreFilters,
                    );
                    if (result != null && mounted) {
                      setState(() => _exploreFilters = result);
                    }
                  },
                  activeFilterCount: _exploreFilters.activeCount,
                ),
              ),
              if (_exploreFilters.hasActiveFilters) ...[
                const SizedBox(height: 10),
                SdLibRestaurantFilterStrip(
                  theme: theme,
                  filters: _exploreFilters,
                  onChanged: (f) => setState(() => _exploreFilters = f),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    final searchQuery = value.text.trim();
                    return StreamBuilder<QuerySnapshot>(
                      stream: _firestore.collection('restaurants').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return _buildRestaurantListSkeleton(theme);
                        }
                        if (snapshot.hasError) {
                          debugPrint(
                              '[UserHome] Restaurants stream error: ${snapshot.error}');
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (context.mounted) {
                              showAppToast(
                                context,
                                'Unable to load restaurants. Please refresh and try again.',
                              );
                            }
                          });
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(RadixIcons.crossCircled,
                                    size: 48,
                                    color: theme.colorScheme.destructive),
                                const SizedBox(height: 16),
                                const Text('Unable to load restaurants').semiBold(),
                                const SizedBox(height: 8),
                                const Text('Please refresh and try again')
                                    .muted()
                                    .small(),
                              ],
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(RadixIcons.home,
                                    size: 48,
                                    color: theme.colorScheme.mutedForeground),
                                const SizedBox(height: 16),
                                Text(
                                  cityDisplay.isNotEmpty
                                      ? 'No restaurants in $cityDisplay yet'
                                      : 'No restaurants in your area yet',
                                ).muted(),
                              ],
                            ),
                          );
                        }
                        final allDocs = snapshot.data!.docs;
                        final restaurants = allDocs
                            .where((d) =>
                                _passesExploreFilters(d, userCityKey, searchQuery))
                            .toList();
                        if (restaurants.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  RadixIcons.magnifyingGlass,
                                  size: 48,
                                  color: theme.colorScheme.mutedForeground,
                                ),
                                const SizedBox(height: 16),
                                const Text('No matching restaurants').semiBold(),
                                const SizedBox(height: 8),
                                Text(
                                  _exploreFilters.hasActiveFilters ||
                                          searchQuery.isNotEmpty
                                      ? 'Try a different search or adjust filters.'
                                      : 'No places match your city and filters.',
                                  textAlign: TextAlign.center,
                                ).muted().small(),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: restaurants.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final restaurant = restaurants[index].data()
                                as Map<String, dynamic>;
                            final restaurantId = restaurants[index].id;
                            return _buildRestaurantCard(
                                theme, restaurant, restaurantId);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _passesExploreFilters(
    QueryDocumentSnapshot<Object?> doc,
    String? userCityKey,
    String searchQuery,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    if (!restaurantCityMatchesUserExplore(userCityKey, data)) {
      return false;
    }
    if (!restaurantMatchesExploreSearch(data, searchQuery)) {
      return false;
    }
    final catFilter = _exploreFilters.categoryId;
    if (catFilter != null) {
      final cat = data['restaurantCategory'] as String?;
      if (cat != catFilter) return false;
    }
    if (_exploreFilters.openNowOnly && !isRestaurantOpenNow(data)) {
      return false;
    }
    return true;
  }

  Widget _buildRestaurantListSkeleton(ThemeData theme) {
    return Skeletonizer(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Bone(
                  width: double.infinity,
                  height: 140,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                Card(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Bone.text(words: 2),
                      const SizedBox(height: 8),
                      const Bone.text(words: 4, fontSize: 12),
                      const SizedBox(height: 8),
                      const Bone.text(words: 3, fontSize: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRestaurantCard(
    ThemeData theme,
    Map<String, dynamic> restaurant,
    String restaurantId,
  ) {
    final coverRaw = restaurant['coverImageUrl'] as String?;
    final profileRaw = restaurant['profileImageUrl'] as String?;
    final cardImageUrl = (coverRaw != null && coverRaw.trim().isNotEmpty)
        ? coverRaw.trim()
        : (profileRaw != null && profileRaw.trim().isNotEmpty
            ? profileRaw.trim()
            : null);
    final name = restaurant['restaurantName'] ?? 'Restaurant';
    final address = restaurant['address'] ?? '';
    final avgRating = (restaurant['averageRating'] as num?)?.toDouble();
    final totalReviews = (restaurant['totalReviews'] as int?) ?? 0;
    final isOpen = isRestaurantOpenNow(restaurant);
    final openTime = restaurant['openTime'] as String?;
    final closeTime = restaurant['closeTime'] as String?;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RestaurantDetailView(
              restaurantId: restaurantId,
              restaurantName: name,
              onCartChanged: () {
                setState(() {});
                widget.onCartChanged?.call();
              },
              onViewCart: widget.onViewCart,
            ),
          ),
        ).then((_) {
          setState(() {});
          widget.onCartChanged?.call();
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              width: double.infinity,
              child: cardImageUrl != null
                  ? Image.network(
                      cardImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _coverPlaceholder(theme),
                    )
                  : _coverPlaceholder(theme),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name).semiBold()),
                      _buildStarRating(theme, avgRating ?? 0, totalReviews),
                    ],
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(RadixIcons.pinTop,
                            size: 12,
                            color: theme.colorScheme.mutedForeground),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ).muted().small(),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? Colors.green.withAlpha(25)
                              : Colors.red.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOpen ? 'OPEN' : 'CLOSED',
                          style: TextStyle(
                            color: isOpen ? Colors.green : Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (openTime != null && closeTime != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '$openTime - $closeTime',
                          style: TextStyle(
                            color: theme.colorScheme.mutedForeground,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const Spacer(),
                      _RestaurantSdLibCategoryBadge(
                        categoryId:
                            restaurant['restaurantCategory'] as String?,
                        theme: theme,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating(ThemeData theme, double rating, int reviewCount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          final starValue = i + 1;
          Color starColor;
          if (rating >= starValue) {
            starColor = Colors.amber;
          } else if (rating >= starValue - 0.5) {
            starColor = Colors.amber.withValues(alpha: 0.5);
          } else {
            starColor = theme.colorScheme.muted;
          }
          return Icon(RadixIcons.star, size: 14, color: starColor);
        }),
        if (reviewCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '($reviewCount)',
            style: TextStyle(
              color: theme.colorScheme.mutedForeground,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _coverPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.primary.withValues(alpha: 0.06),
      child: Center(
        child: Icon(RadixIcons.home,
            size: 40, color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
    );
  }
}

/// SD-lib: shows the restaurant's registered category (not menu tags).
class _RestaurantSdLibCategoryBadge extends StatelessWidget {
  final String? categoryId;
  final ThemeData theme;

  const _RestaurantSdLibCategoryBadge({
    required this.categoryId,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final label = sdLibRestaurantCategoryLabel(categoryId);
    if (label == null) return const SizedBox.shrink();

    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

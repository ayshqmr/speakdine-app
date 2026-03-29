import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/services/payment_service.dart';
import 'package:speak_dine/utils/pkr_format.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/view/restaurant/restaurant_merchant_reviews.dart';
import 'package:url_launcher/url_launcher.dart';

bool _isSameCalendarDay(Timestamp? ts, DateTime day) {
  if (ts == null) return false;
  final d = ts.toDate();
  return d.year == day.year && d.month == day.month && d.day == day.day;
}

int _liveOrderCount(Iterable<QueryDocumentSnapshot<Object?>> docs) {
  var n = 0;
  for (final d in docs) {
    final m = d.data() as Map<String, dynamic>?;
    final s = m?['status']?.toString() ?? '';
    if (s != 'delivered') n++;
  }
  return n;
}

int _ordersCreatedToday(Iterable<QueryDocumentSnapshot<Object?>> docs) {
  final now = DateTime.now();
  var n = 0;
  for (final d in docs) {
    final m = d.data() as Map<String, dynamic>?;
    final ts = m?['createdAt'];
    if (ts is Timestamp && _isSameCalendarDay(ts, now)) n++;
  }
  return n;
}

double _revenueDeliveredToday(Iterable<QueryDocumentSnapshot<Object?>> docs) {
  final now = DateTime.now();
  var sum = 0.0;
  for (final d in docs) {
    final m = d.data() as Map<String, dynamic>?;
    if (m == null) continue;
    if (m['status']?.toString() != 'delivered') continue;
    final ts = m['createdAt'];
    if (ts is! Timestamp || !_isSameCalendarDay(ts, now)) continue;
    final t = m['total'];
    if (t is num) sum += t.toDouble();
  }
  return sum;
}

String _greetingLine() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Same name keys as [RestaurantProfileView] / signup so the home title matches Profile.
String? _venueNameFromDoc(Map<String, dynamic>? m) {
  if (m == null) return null;
  for (final key in [
    'restaurantName',
    'name',
    'businessName',
    'signInRestaurantName',
  ]) {
    final v = m[key];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

/// Display line under greeting; [isLoading] uses muted style without "set name" copy.
({String text, bool isPlaceholder, bool isLoading}) _venueTitleLine(
  AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> restSnap,
) {
  if (!restSnap.hasData) {
    return (text: 'Loading…', isPlaceholder: true, isLoading: true);
  }
  final doc = restSnap.data!;
  if (!doc.exists) {
    return (
      text: 'Set up your venue in Profile',
      isPlaceholder: true,
      isLoading: false,
    );
  }
  final nameRaw = _venueNameFromDoc(doc.data());
  if (nameRaw == null || nameRaw.isEmpty) {
    return (
      text: 'Set your venue name in Profile',
      isPlaceholder: true,
      isLoading: false,
    );
  }
  return (text: nameRaw, isPlaceholder: false, isLoading: false);
}

/// Merchant home: greeting, horizontal metrics, quick actions, dishes row.
class RestaurantDashboardView extends StatelessWidget {
  const RestaurantDashboardView({
    super.key,
    required this.onNavigateToTab,
    this.onNavigateToMenuAndAddDish,
  });

  final ValueChanged<int> onNavigateToTab;
  final VoidCallback? onNavigateToMenuAndAddDish;

  Future<void> _openStripeDashboard(
    BuildContext context, {
    required String? accountId,
    required bool onboarded,
  }) async {
    if (!onboarded) {
      showAppToast(context, 'Complete Stripe setup in Profile first.');
      return;
    }
    if (accountId == null || accountId.isEmpty) return;
    final url = await PaymentService.getConnectDashboardLink(accountId: accountId);
    if (url == null) {
      if (context.mounted) {
        showAppToast(context, 'Could not open Stripe. Try again.');
      }
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, webOnlyWindowName: '_self');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }
    final uid = user.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(uid)
          .snapshots(),
      builder: (context, restSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('restaurants')
              .doc(uid)
              .collection('orders')
              .snapshots(),
          builder: (context, ordSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(uid)
                  .collection('menu')
                  .snapshots(),
              builder: (context, menuSnap) {
                final venue = _venueTitleLine(restSnap);
                final data = restSnap.data?.data();
                final catLabel = sdLibRestaurantCategoryLabel(
                    data?['restaurantCategory'] as String?);
                final stripeAccountId = data?['stripeConnectId'] as String?;
                final onboarded =
                    data?['stripeConnectOnboarded'] == true;

                final orderDocs = ordSnap.data?.docs ?? [];
                final live = _liveOrderCount(orderDocs);
                final ordersToday = _ordersCreatedToday(orderDocs);
                final revenueToday = _revenueDeliveredToday(orderDocs);
                final menuCount = menuSnap.data?.docs.length ?? 0;

                final primary = theme.colorScheme.primary;
                final onPrimary = theme.colorScheme.primaryForeground;
                final scrollW = MediaQuery.sizeOf(context).width - 40;
                final cardWidth = (scrollW * 0.82).clamp(252.0, 308.0);

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greetingLine()).muted().small(),
                      const SizedBox(height: 4),
                      if (venue.isLoading)
                        Text(venue.text).muted().h4().semiBold()
                      else if (venue.isPlaceholder)
                        Text(venue.text).muted().h4().semiBold()
                      else
                        Text(venue.text).h4().semiBold(),
                      if (catLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Your venue type: $catLabel',
                        ).muted().small(),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 192,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: GestureDetector(
                                onTap: () => _openStripeDashboard(
                                  context,
                                  accountId: stripeAccountId,
                                  onboarded: onboarded,
                                ),
                                child: _SalesMetricCarouselCard(
                                  theme: theme,
                                  primary: primary,
                                  onPrimary: onPrimary,
                                  revenueToday: revenueToday,
                                  onboarded: onboarded,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: cardWidth,
                              child: _MetricCarouselCard(
                                theme: theme,
                                variant: _MetricCardVariant.softPink,
                                valueText: '$live',
                                label: 'ACTIVE ORDERS',
                                subtitle: 'Not delivered yet',
                                onTap: () => onNavigateToTab(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: cardWidth,
                              child: _MetricCarouselCard(
                                theme: theme,
                                variant: _MetricCardVariant.lightGray,
                                valueText: '$ordersToday',
                                label: 'ORDERS TODAY',
                                subtitle: 'Placed today',
                                onTap: () => onNavigateToTab(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: cardWidth,
                              child: _MetricCarouselCard(
                                theme: theme,
                                variant: _MetricCardVariant.pinkGray,
                                valueText: '$menuCount',
                                label: 'DISHES',
                                subtitle: menuCount == 1
                                    ? '1 menu item'
                                    : '$menuCount menu items',
                                onTap: () => onNavigateToTab(1),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text('Quick actions').semiBold(),
                      const SizedBox(height: 12),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        // Keep cards compact; adjust icon panel instead.
                        childAspectRatio: 1.25,
                        children: [
                          _QuickActionTile(
                            theme: theme,
                            icon: RadixIcons.lightningBolt,
                            iconBg: const Color(0xFFFFE4D6),
                            iconColor: const Color(0xFFE85D04),
                            title: 'Live orders',
                            subtitle: '$live active',
                            onTap: () => onNavigateToTab(2),
                          ),
                          _QuickActionTile(
                            theme: theme,
                            icon: RadixIcons.reader,
                            iconBg: const Color(0xFFE8E0FF),
                            iconColor: const Color(0xFF6D28D9),
                            title: 'Menu',
                            subtitle:
                                menuCount == 1 ? '1 item' : '$menuCount items',
                            onTap: () => onNavigateToTab(1),
                          ),
                          _QuickActionTile(
                            theme: theme,
                            icon: RadixIcons.barChart,
                            iconBg: const Color(0xFFD8F3F0),
                            iconColor: const Color(0xFF0F766E),
                            title: 'Analytics',
                            subtitle: 'Stripe',
                            onTap: () => _openStripeDashboard(
                              context,
                              accountId: stripeAccountId,
                              onboarded: onboarded,
                            ),
                          ),
                          _QuickActionTile(
                            theme: theme,
                            icon: RadixIcons.cardStack,
                            iconBg: const Color(0xFFFFF3D6),
                            iconColor: const Color(0xFFB45309),
                            title: 'Payments',
                            subtitle: 'Transactions',
                            onTap: () => onNavigateToTab(3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                theme.colorScheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: RestaurantMerchantReviewsSection(
                          restaurantId: uid,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _DishesShortcutCard(
                        theme: theme,
                        onOpenList: () => onNavigateToTab(1),
                        onAddDish: onNavigateToMenuAndAddDish,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SalesMetricCarouselCard extends StatelessWidget {
  const _SalesMetricCarouselCard({
    required this.theme,
    required this.primary,
    required this.onPrimary,
    required this.revenueToday,
    required this.onboarded,
  });

  final ThemeData theme;
  final Color primary;
  final Color onPrimary;
  final double revenueToday;
  final bool onboarded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: onPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  RadixIcons.cardStack,
                  size: 20,
                  color: onPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: onPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  onboarded ? 'Stripe' : 'Setup',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            formatPkr(revenueToday),
            style: TextStyle(
              color: onPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SALES TODAY (DELIVERED)',
            style: TextStyle(
              color: onPrimary.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap · Stripe Dashboard',
            style: TextStyle(
              color: onPrimary.withValues(alpha: 0.75),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MetricCardVariant { softPink, lightGray, pinkGray }

Color _metricCarouselCardBackground(ThemeData theme, _MetricCardVariant v) {
  final bg = theme.colorScheme.background;
  final primary = theme.colorScheme.primary;
  switch (v) {
    case _MetricCardVariant.softPink:
      return Color.alphaBlend(primary.withValues(alpha: 0.14), bg);
    case _MetricCardVariant.lightGray:
      final neutral = Color.lerp(bg, const Color(0xFFC8C4CC), 0.22)!;
      return Color.alphaBlend(
        const Color(0xFF6B6570).withValues(alpha: 0.06),
        neutral,
      );
    case _MetricCardVariant.pinkGray:
      final grayPinkBase = Color.lerp(bg, primary, 0.06)!;
      return Color.alphaBlend(primary.withValues(alpha: 0.08), grayPinkBase);
  }
}

class _MetricCarouselCard extends StatelessWidget {
  const _MetricCarouselCard({
    required this.theme,
    required this.variant,
    required this.valueText,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final ThemeData theme;
  final _MetricCardVariant variant;
  final String valueText;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = _metricCarouselCardBackground(theme, variant);
    final valueColor = theme.colorScheme.foreground;
    final labelColor = Color.lerp(
      theme.colorScheme.foreground,
      theme.colorScheme.primary,
      0.4,
    )!;
    final subtitleColor = theme.colorScheme.mutedForeground;
    final borderColor = theme.colorScheme.primary.withValues(alpha: 0.2);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.foreground.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Text(
              valueText,
              style: TextStyle(
                color: valueColor,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.theme,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final ThemeData theme;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 96,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(icon, size: 42, color: iconColor),
              ),
            ),
            const Spacer(),
            Text(title).semiBold(),
            const SizedBox(height: 2),
            Text(subtitle).muted().small(),
          ],
        ),
      ),
    );
  }
}

class _DishesShortcutCard extends StatelessWidget {
  const _DishesShortcutCard({
    required this.theme,
    required this.onOpenList,
    required this.onAddDish,
  });

  final ThemeData theme;
  final VoidCallback onOpenList;
  final VoidCallback? onAddDish;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenList,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      RadixIcons.rows,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('All dishes').semiBold(),
                        const SizedBox(height: 2),
                        const Text('View your menu').muted().small(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          GhostButton(
            density: ButtonDensity.compact,
            onPressed: onAddDish,
            child: Icon(
              RadixIcons.plus,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' as material
    show MaterialPageRoute, SingleChildScrollView;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Shown under the customer name (review / order completion time from Firestore).
String _formatReviewDateTime(DateTime date) {
  return DateFormat('d MMM y · h:mm a').format(date);
}

void _openAllReviews(BuildContext context, String restaurantId) {
  Navigator.of(context).push(
    material.MaterialPageRoute<void>(
      builder: (_) => RestaurantMerchantAllReviewsPage(
        restaurantId: restaurantId,
      ),
    ),
  );
}

/// Merchant home / dashboard: latest 3 reviews (horizontal scroll) + circular “see all” after cards.
class RestaurantMerchantReviewsSection extends StatelessWidget {
  const RestaurantMerchantReviewsSection({
    super.key,
    required this.restaurantId,
  });

  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('restaurants')
          .doc(restaurantId)
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final hasData = snapshot.hasData;
        final waiting = snapshot.connectionState == ConnectionState.waiting;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reviews').semiBold(),
            const SizedBox(height: 10),
            if (waiting && !hasData)
              SizedBox(
                height: 120,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              )
            else if (docs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.border.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'No reviews yet. Customers can leave a review after a delivered order.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              )
            else
              SizedBox(
                height: 158,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length + 1,
                  itemBuilder: (context, index) {
                    if (index < docs.length) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 268,
                          child: _MerchantReviewPreviewCard(
                            theme: theme,
                            review: data,
                          ),
                        ),
                      );
                    }
                    return _MerchantReviewsSeeAllFab(
                      theme: theme,
                      onPressed: () => _openAllReviews(context, restaurantId),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Circular primary control at the end of the preview row (opens all reviews).
class _MerchantReviewsSeeAllFab extends StatelessWidget {
  const _MerchantReviewsSeeAllFab({
    required this.theme,
    required this.onPressed,
  });

  final ThemeData theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Center(
        child: GestureDetector(
          onTap: onPressed,
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
}

class _MerchantReviewPreviewCard extends StatelessWidget {
  const _MerchantReviewPreviewCard({
    required this.theme,
    required this.review,
  });

  final ThemeData theme;
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = review['rating'] as int? ?? 0;
    final comment = review['comment'] as String? ?? '';
    final customerName = review['customerName'] as String? ?? 'Customer';
    final createdAt = review['createdAt'] as Timestamp?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.35),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customerName).semiBold().small(),
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
      ),
    );
  }
}

class RestaurantMerchantAllReviewsPage extends StatelessWidget {
  const RestaurantMerchantAllReviewsPage({
    super.key,
    required this.restaurantId,
  });

  final String restaurantId;

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
                        final data = doc.data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MerchantReviewFullCard(
                            theme: theme,
                            review: data,
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

class _MerchantReviewFullCard extends StatelessWidget {
  const _MerchantReviewFullCard({
    required this.theme,
    required this.review,
  });

  final ThemeData theme;
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = review['rating'] as int? ?? 0;
    final comment = review['comment'] as String? ?? '';
    final customerName = review['customerName'] as String? ?? 'Customer';
    final createdAt = review['createdAt'] as Timestamp?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.35),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customerName).semiBold(),
                    if (createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatReviewDateTime(createdAt.toDate()),
                        style: TextStyle(
                          fontSize: 12,
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
                    size: 16,
                    color: i < rating
                        ? theme.colorScheme.primary
                        : theme.colorScheme.muted,
                  ),
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comment).muted().small(),
          ],
        ],
      ),
    );
  }
}

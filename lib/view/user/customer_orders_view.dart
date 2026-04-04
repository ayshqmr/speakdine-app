import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/view/user/order_tracking_view.dart';
import 'package:speak_dine/view/user/review_dialog.dart';
import 'package:speak_dine/utils/pkr_format.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';

const _activeStatuses = {
  'pending',
  'accepted',
  'in_kitchen',
  'handed_to_rider',
  'on_the_way',
};

const _statusDisplayLabels = {
  'pending': 'Pending',
  'accepted': 'Accepted',
  'in_kitchen': 'In Kitchen',
  'handed_to_rider': 'With Rider',
  'on_the_way': 'On the Way',
  'delivered': 'Delivered',
};

class CustomerOrdersView extends StatelessWidget {
  /// When opened from Profile (pushed route), show a back control. The Orders tab
  /// uses [showBackButton] false — same widget, embedded in [CustomerShell].
  const CustomerOrdersView({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(showBackButton ? 4 : 20, 16, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBackButton) ...[
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(RadixIcons.arrowLeft, size: 16),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('My Orders').h4().semiBold(),
                    const Text('Track and review your past orders').muted().small(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user?.uid)
                .collection('orders')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildSkeleton();
              }
              if (snapshot.hasError) {
                debugPrint(
                  '[CustomerOrders] Orders stream error: ${snapshot.error}',
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    showAppToast(
                      context,
                      'Unable to load orders. Please try again.',
                    );
                  }
                });
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        RadixIcons.crossCircled,
                        size: 48,
                        color: theme.colorScheme.destructive,
                      ),
                      const SizedBox(height: 16),
                      const Text('Unable to load orders').semiBold(),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                CustomerVoiceBridge.instance.openPendingReviewDialog = null;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        RadixIcons.archive,
                        size: 48,
                        color: theme.colorScheme.mutedForeground,
                      ),
                      const SizedBox(height: 16),
                      const Text('No orders yet').semiBold(),
                      const SizedBox(height: 8),
                      const Text(
                        'Your order history will appear here',
                      ).muted().small(),
                    ],
                  ),
                );
              }
              final orders = snapshot.data!.docs;
              final pendingReviewDoc = orders
                  .cast<QueryDocumentSnapshot>()
                  .firstWhere((doc) {
                    final order = doc.data() as Map<String, dynamic>;
                    final isDelivered =
                        (order['status'] as String? ?? '') == 'delivered';
                    final reviewed = order['reviewed'] == true;
                    return isDelivered && !reviewed;
                  }, orElse: () => orders.first);
              final pendingData =
                  pendingReviewDoc.data() as Map<String, dynamic>;
              final hasPendingReview =
                  (pendingData['status'] as String? ?? '') == 'delivered' &&
                  pendingData['reviewed'] != true;

              CustomerVoiceBridge.instance.openPendingReviewDialog =
                  hasPendingReview
                  ? () async {
                      showReviewDialog(
                        context,
                        restaurantId: pendingData['restaurantId'] ?? '',
                        restaurantName:
                            pendingData['restaurantName'] ?? 'Restaurant',
                        orderId: pendingReviewDoc.id,
                        customerId: user?.uid ?? '',
                        customerName: pendingData['customerName'] ?? 'Customer',
                      );
                      return null;
                    }
                  : () async =>
                        'You do not have any delivered order pending review.';

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final doc = orders[index];
                  final order = doc.data() as Map<String, dynamic>;
                  return _buildOrderCard(context, theme, order, doc.id, user);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return Skeletonizer(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Bone.text(words: 2),
                  const SizedBox(height: 8),
                  const Bone.text(words: 3, fontSize: 12),
                  const SizedBox(height: 8),
                  const Bone.text(words: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    ThemeData theme,
    Map<String, dynamic> order,
    String orderId,
    User? user,
  ) {
    final status = order['status'] as String? ?? 'pending';
    final restaurantName = order['restaurantName'] ?? 'Restaurant';
    final itemCount = order['itemCount'] ?? 0;
    final isActive = _activeStatuses.contains(status);
    final isDelivered = status == 'delivered';
    final reviewed = order['reviewed'] == true;

    return GestureDetector(
      onTap: isActive || isDelivered
          ? () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => OrderTrackingView(
                    orderId: orderId,
                    restaurantName: restaurantName,
                  ),
                ),
              );
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                : theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(restaurantName).semiBold()),
                _buildPaymentChip(theme, order),
                const SizedBox(width: 6),
                _buildStatusChip(theme, status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  RadixIcons.archive,
                  size: 14,
                  color: theme.colorScheme.mutedForeground,
                ),
                const SizedBox(width: 6),
                Text('$itemCount items').muted().small(),
                const Spacer(),
                Text(
                  formatPkr(order['total']),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    RadixIcons.arrowRight,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to track',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            if (isDelivered && !reviewed) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlineButton(
                  density: ButtonDensity.compact,
                  onPressed: () {
                    showReviewDialog(
                      context,
                      restaurantId: order['restaurantId'] ?? '',
                      restaurantName: restaurantName,
                      orderId: orderId,
                      customerId: user?.uid ?? '',
                      customerName: order['customerName'] ?? 'Customer',
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        RadixIcons.star,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      const Text('Rate & Review'),
                    ],
                  ),
                ),
              ),
            ],
            if (isDelivered && reviewed) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      RadixIcons.checkCircled,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Reviewed',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentChip(ThemeData theme, Map<String, dynamic> order) {
    final paymentMethod = order['paymentMethod'] as String? ?? 'cod';
    final paymentStatus = order['paymentStatus'] as String? ?? 'pending';

    final bool isPaid = paymentStatus == 'paid';
    final bool isCod = paymentMethod == 'cod';

    final String label;
    final Color bgColor;
    final Color textColor;

    if (isCod) {
      label = 'COD';
      bgColor = Colors.orange.withAlpha(30);
      textColor = Colors.orange;
    } else if (isPaid) {
      label = 'PAID';
      bgColor = Colors.green.withAlpha(30);
      textColor = Colors.green;
    } else {
      label = 'UNPAID';
      bgColor = Colors.red.withAlpha(30);
      textColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, String status) {
    Color bgColor;
    Color textColor;
    switch (status) {
      case 'pending':
        bgColor = Colors.orange.withAlpha(30);
        textColor = Colors.orange;
      case 'accepted':
        bgColor = Colors.blue.withAlpha(30);
        textColor = Colors.blue;
      case 'in_kitchen':
        bgColor = Colors.indigo.withAlpha(30);
        textColor = Colors.indigo;
      case 'handed_to_rider':
        bgColor = Colors.purple.withAlpha(30);
        textColor = Colors.purple;
      case 'on_the_way':
        bgColor = Colors.teal.withAlpha(30);
        textColor = Colors.teal;
      case 'delivered':
        bgColor = Colors.green.withAlpha(30);
        textColor = Colors.green;
      default:
        bgColor = theme.colorScheme.muted;
        textColor = theme.colorScheme.mutedForeground;
    }

    final label = _statusDisplayLabels[status] ?? status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

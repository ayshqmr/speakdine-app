import 'dart:async';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/view/user/review_dialog.dart';
import 'package:speak_dine/utils/pkr_format.dart';
import 'package:speak_dine/widgets/customer_voice_fab.dart';

const _trackingStages = [
  _TrackingStage(
    status: 'accepted',
    title: 'Processing',
    subtitle: 'Your order has been accepted',
    icon: RadixIcons.checkCircled,
  ),
  _TrackingStage(
    status: 'in_kitchen',
    title: 'In the Kitchen',
    subtitle: 'Your food is being prepared',
    icon: RadixIcons.timer,
  ),
  _TrackingStage(
    status: 'handed_to_rider',
    title: 'Handed to Rider',
    subtitle: 'Your order is on its way',
    icon: RadixIcons.rocket,
  ),
  _TrackingStage(
    status: 'on_the_way',
    title: 'On the Way',
    subtitle: 'Almost there!',
    icon: RadixIcons.paperPlane,
  ),
];

class _TrackingStage {
  final String status;
  final String title;
  final String subtitle;
  final IconData icon;
  const _TrackingStage({
    required this.status,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class OrderTrackingView extends StatelessWidget {
  final String orderId;
  final String restaurantName;

  const OrderTrackingView({
    super.key,
    required this.orderId,
    required this.restaurantName,
  });

  int _statusIndex(String status) {
    for (int i = 0; i < _trackingStages.length; i++) {
      if (_trackingStages[i].status == status) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      child: Container(
        color: theme.colorScheme.background,
        child: SafeArea(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Order Tracking').h4().semiBold(),
                              Text(restaurantName).muted().small(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user?.uid)
                          .collection('orders')
                          .doc(orderId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: theme.colorScheme.primary,
                            ),
                          );
                        }
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const Center(
                            child: Text('Order not found'),
                          );
                        }

                        final order =
                            snapshot.data!.data() as Map<String, dynamic>;
                        final status = order['status'] as String? ?? 'pending';
                        final estimatedMinutes =
                            order['estimatedMinutes'] as int?;
                        final acceptedAt =
                            order['acceptedAt'] as Timestamp?;
                        final isDelivered = status == 'delivered';
                        final reviewed = order['reviewed'] == true;
                        final currentStageIndex = _statusIndex(status);

                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              if (estimatedMinutes != null &&
                                  acceptedAt != null &&
                                  !isDelivered) ...[
                                _EtaCountdownCard(
                                  estimatedMinutes: estimatedMinutes,
                                  acceptedAt: acceptedAt,
                                ),
                                const SizedBox(height: 24),
                              ],
                              if (isDelivered) ...[
                                _buildDeliveredCard(theme),
                                const SizedBox(height: 24),
                              ],
                              _buildTrackingStepper(
                                  theme, currentStageIndex, isDelivered),
                              if (isDelivered && !reviewed) ...[
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  child: PrimaryButton(
                                    onPressed: () {
                                      showReviewDialog(
                                        context,
                                        restaurantId:
                                            order['restaurantId'] ?? '',
                                        restaurantName: restaurantName,
                                        orderId: orderId,
                                        customerId: user?.uid ?? '',
                                        customerName:
                                            order['customerName'] ?? 'Customer',
                                      );
                                    },
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(RadixIcons.star, size: 16),
                                        SizedBox(width: 8),
                                        Text('Rate Your Experience'),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (isDelivered && reviewed) ...[
                                const SizedBox(height: 32),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.22),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        RadixIcons.checkCircled,
                                        size: 18,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Reviewed',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              _buildOrderDetails(theme, order),
                              const SizedBox(height: 32),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const CustomerVoiceFabPositioned(hasBottomDock: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveredCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(RadixIcons.checkCircled, size: 36, color: Colors.green),
          const SizedBox(height: 8),
          Text(
            'Delivered!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 4),
          const Text('Enjoy your meal!').muted().small(),
        ],
      ),
    );
  }

  Widget _buildTrackingStepper(ThemeData theme, int currentStageIndex, bool isDelivered) {
    return Column(
      children: List.generate(_trackingStages.length, (index) {
        final stage = _trackingStages[index];
        final isCompleted = isDelivered || index < currentStageIndex;
        final isActive = !isDelivered && index == currentStageIndex;
        final isPending = !isDelivered && index > currentStageIndex;

        Color circleColor;
        Color iconColor;
        Color lineColor;

        if (isCompleted || isDelivered) {
          circleColor = theme.colorScheme.primary;
          iconColor = Colors.white;
          lineColor = theme.colorScheme.primary;
        } else if (isActive) {
          circleColor = theme.colorScheme.primary;
          iconColor = Colors.white;
          lineColor = theme.colorScheme.primary.withValues(alpha: 0.2);
        } else {
          circleColor = theme.colorScheme.muted;
          iconColor = theme.colorScheme.mutedForeground;
          lineColor = theme.colorScheme.muted;
        }

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(stage.icon, size: 18, color: iconColor),
                    ),
                    if (index < _trackingStages.length - 1)
                      Container(
                        width: 3,
                        height: 40,
                        color: lineColor,
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stage.title,
                          style: TextStyle(
                            fontWeight: isActive || isCompleted
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isPending
                                ? theme.colorScheme.mutedForeground
                                : theme.colorScheme.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stage.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isCompleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Icon(RadixIcons.check, size: 16, color: theme.colorScheme.primary),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _buildOrderDetails(ThemeData theme, Map<String, dynamic> order) {
    final items = order['items'] as List<dynamic>? ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          const Text('Order Details').semiBold(),
          const SizedBox(height: 12),
          ...items.map((item) {
            final itemMap = item as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('${itemMap['quantity']}x ${itemMap['name']}').small(),
                  ),
                  Text(formatPkr(itemMap['itemTotal']),
                      style: TextStyle(color: theme.colorScheme.primary)),
                ],
              ),
            );
          }),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total').semiBold(),
              Text(
                formatPkr(order['total']),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EtaCountdownCard extends StatefulWidget {
  final int estimatedMinutes;
  final Timestamp acceptedAt;

  const _EtaCountdownCard({
    required this.estimatedMinutes,
    required this.acceptedAt,
  });

  @override
  State<_EtaCountdownCard> createState() => _EtaCountdownCardState();
}

class _EtaCountdownCardState extends State<_EtaCountdownCard> {
  late final DateTime _deliveryTime;
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    final acceptedTime = widget.acceptedAt.toDate();
    _deliveryTime = acceptedTime.add(Duration(minutes: widget.estimatedMinutes));
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemaining();
    });
  }

  void _updateRemaining() {
    final diff = _deliveryTime.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          const Text('Estimated Delivery').muted().small(),
          const SizedBox(height: 8),
          Text(
            _remaining == Duration.zero
                ? 'Any moment now!'
                : '${minutes}m ${seconds.toString().padLeft(2, '0')}s',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

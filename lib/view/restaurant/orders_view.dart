import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:speak_dine/utils/pkr_format.dart';

const _statusFlow = ['pending', 'accepted', 'in_kitchen', 'handed_to_rider', 'on_the_way', 'delivered'];

const _statusLabels = {
  'pending': 'Pending',
  'accepted': 'Accepted',
  'in_kitchen': 'In Kitchen',
  'handed_to_rider': 'Handed to Rider',
  'on_the_way': 'On the Way',
  'delivered': 'Delivered',
};

class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Orders').h4().semiBold(),
              const Text('Manage incoming customer orders')
                  .muted()
                  .small(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('restaurants')
                .doc(user?.uid)
                .collection('orders')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildOrdersSkeleton();
              }
              if (snapshot.hasError) {
                debugPrint('[RestaurantOrders] Orders stream error: ${snapshot.error}');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    showAppToast(context, 'Unable to load orders. Please try again.');
                  }
                });
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(RadixIcons.crossCircled,
                          size: 48, color: theme.colorScheme.destructive),
                      const SizedBox(height: 16),
                      const Text('Unable to load orders').semiBold(),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(RadixIcons.archive,
                          size: 48, color: theme.colorScheme.mutedForeground),
                      const SizedBox(height: 16),
                      const Text('No orders yet').semiBold(),
                      const SizedBox(height: 8),
                      const Text('Orders will appear here when\ncustomers place them')
                          .muted()
                          .small(),
                    ],
                  ),
                );
              }
              final orders = snapshot.data!.docs;
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final order = orders[index].data() as Map<String, dynamic>;
                  final orderId = orders[index].id;
                  return _buildOrderCard(theme, order, orderId);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersSkeleton() {
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Bone.text(words: 2),
                      const Bone(width: 72, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
                    ],
                  ),
                  const Divider(height: 24),
                  const Bone.text(words: 3, fontSize: 12),
                  const SizedBox(height: 8),
                  const Bone.text(words: 2, fontSize: 12),
                  const SizedBox(height: 8),
                  const Bone.text(words: 1),
                  const SizedBox(height: 16),
                  const Bone(width: double.infinity, height: 36, borderRadius: BorderRadius.all(Radius.circular(8))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(
      ThemeData theme, Map<String, dynamic> order, String orderId) {
    final status = order['status'] ?? 'pending';
    final customerLat = (order['customerLat'] as num?)?.toDouble();
    final customerLng = (order['customerLng'] as num?)?.toDouble();
    final customerAddress = order['customerAddress'] as String?;
    final estimatedMinutes = order['estimatedMinutes'] as int?;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Order #${orderId.substring(0, 6).toUpperCase()}')
                    .semiBold(),
              ),
              _buildPaymentBadge(theme, order),
              const SizedBox(width: 6),
              _buildStatusBadge(theme, status),
            ],
          ),
          const Divider(height: 24),
          Text('Customer: ${order['customerName'] ?? 'Unknown'}')
              .muted()
              .small(),
          const SizedBox(height: 4),
          Text('Items: ${order['itemCount'] ?? 0}').muted().small(),
          if (customerAddress != null && customerAddress.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(RadixIcons.pinTop, size: 12, color: theme.colorScheme.mutedForeground),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(customerAddress, maxLines: 1, overflow: TextOverflow.ellipsis)
                      .muted()
                      .small(),
                ),
              ],
            ),
          ],
          if (estimatedMinutes != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(RadixIcons.clock, size: 12, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('ETA: $estimatedMinutes min',
                    style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            formatPkr(order['total']),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (customerLat != null && customerLng != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 120,
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(customerLat, customerLng),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.speakdine.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(customerLat, customerLng),
                            width: 32,
                            height: 32,
                            child: Icon(RadixIcons.crosshair1,
                                size: 32, color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildActionButtons(theme, order, orderId, status),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ThemeData theme, String status) {
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

    final label = _statusLabels[status] ?? status.toUpperCase();

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

  Widget _buildPaymentBadge(ThemeData theme, Map<String, dynamic> order) {
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

  Widget _buildActionButtons(
      ThemeData theme, Map<String, dynamic> order, String orderId, String status) {
    if (status == 'delivered') return const SizedBox.shrink();

    if (status == 'pending') {
      return SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          onPressed: () => _showAcceptDialog(theme, order, orderId),
          child: const Text('Accept Order'),
        ),
      );
    }

    final currentIndex = _statusFlow.indexOf(status);
    if (currentIndex < 0 || currentIndex >= _statusFlow.length - 1) {
      return const SizedBox.shrink();
    }

    final nextStatus = _statusFlow[currentIndex + 1];
    final nextLabel = _statusLabels[nextStatus] ?? nextStatus;

    return SizedBox(
      width: double.infinity,
      child: PrimaryButton(
        onPressed: () => _advanceStatus(orderId, order, nextStatus),
        child: Text('Mark: $nextLabel'),
      ),
    );
  }

  void _showAcceptDialog(ThemeData theme, Map<String, dynamic> order, String orderId) {
    final etaController = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Order'),
        content: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order from ${order['customerName'] ?? 'Customer'}')
                    .muted()
                    .small(),
                const SizedBox(height: 16),
                const Text('Estimated delivery time (minutes)')
                    .semiBold()
                    .small(),
                const SizedBox(height: 6),
                TextField(
                  controller: etaController,
                  placeholder: const Text('30'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            onPressed: () async {
              final minutes = int.tryParse(etaController.text) ?? 30;
              Navigator.pop(ctx);
              await _acceptOrder(orderId, order, minutes);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptOrder(String orderId, Map<String, dynamic> order, int estimatedMinutes) async {
    try {
      await _firestore
          .collection('restaurants')
          .doc(user?.uid)
          .collection('orders')
          .doc(orderId)
          .update({
        'status': 'accepted',
        'estimatedMinutes': estimatedMinutes,
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      final customerId = order['customerId'] as String?;
      final customerOrderId = order['customerOrderId'] as String?;
      if (customerId != null && customerOrderId != null) {
        await _syncCustomerOrderStatus(customerId, customerOrderId, 'accepted',
            estimatedMinutes: estimatedMinutes);

        await NotificationService.createNotification(
          userId: customerId,
          title: 'Order Accepted!',
          message: 'Estimated delivery: $estimatedMinutes minutes',
          orderId: orderId,
        );
      }

      if (!mounted) return;
      showAppToast(context, 'Order accepted');
    } catch (e) {
      debugPrint('[OrdersView] Accept error: $e');
      if (!mounted) return;
      showAppToast(context, 'Something went wrong. Please try again later.');
    }
  }

  Future<void> _advanceStatus(String orderId, Map<String, dynamic> order, String nextStatus) async {
    try {
      await _firestore
          .collection('restaurants')
          .doc(user?.uid)
          .collection('orders')
          .doc(orderId)
          .update({'status': nextStatus});

      final customerId = order['customerId'] as String?;
      final customerOrderId = order['customerOrderId'] as String?;
      if (customerId != null && customerOrderId != null) {
        await _syncCustomerOrderStatus(customerId, customerOrderId, nextStatus);

        if (nextStatus == 'handed_to_rider') {
          await NotificationService.createNotification(
            userId: customerId,
            title: 'Order Picked Up!',
            message: 'Your order has been handed to the rider.',
            orderId: orderId,
          );
        } else if (nextStatus == 'delivered') {
          await NotificationService.createNotification(
            userId: customerId,
            title: 'Order Delivered!',
            message: 'Your order has been delivered. Enjoy your meal!',
            orderId: orderId,
          );
        }
      }

      if (!mounted) return;
      showAppToast(context, 'Status updated to ${_statusLabels[nextStatus] ?? nextStatus}');
    } catch (e) {
      debugPrint('[OrdersView] Status update error: $e');
      if (!mounted) return;
      showAppToast(context, 'Something went wrong. Please try again later.');
    }
  }

  Future<void> _syncCustomerOrderStatus(
      String customerId, String customerOrderId, String status,
      {int? estimatedMinutes}) async {
    try {
      final updateData = <String, dynamic>{'status': status};
      if (estimatedMinutes != null) {
        updateData['estimatedMinutes'] = estimatedMinutes;
        updateData['acceptedAt'] = FieldValue.serverTimestamp();
      }
      await _firestore
          .collection('users')
          .doc(customerId)
          .collection('orders')
          .doc(customerOrderId)
          .update(updateData);
    } catch (e) {
      debugPrint('[OrdersView] Sync customer order error: $e');
    }
  }
}

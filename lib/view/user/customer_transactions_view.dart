import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/utils/pkr_format.dart';

class CustomerTransactionsView extends StatelessWidget {
  const CustomerTransactionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Transactions').h4().semiBold(),
              const Text('Your payment history').muted().small(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: user == null
              ? Center(
                  child: Text('Sign in to see your transactions')
                      .muted()
                      .small(),
                )
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('transactions')
                      .where('customerId', isEqualTo: user.uid)
                      // No orderBy: avoids composite index; sort client-side.
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildSkeleton();
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(RadixIcons.exclamationTriangle,
                                  size: 40,
                                  color: theme.colorScheme.destructive),
                              const SizedBox(height: 12),
                              const Text('Could not load transactions')
                                  .semiBold(),
                              const SizedBox(height: 8),
                              Text(
                                '${snapshot.error}',
                                textAlign: TextAlign.center,
                              ).muted().small(),
                            ],
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(RadixIcons.cardStack,
                                size: 48,
                                color: theme.colorScheme.mutedForeground),
                            const SizedBox(height: 16),
                            const Text('No transactions yet').semiBold(),
                            const SizedBox(height: 8),
                            const Text('Your payments will appear here')
                                .muted()
                                .small(),
                          ],
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs.toList()
                      ..sort((a, b) {
                        final ta = a.data()['createdAt'] as Timestamp?;
                        final tb = b.data()['createdAt'] as Timestamp?;
                        if (ta == null && tb == null) return 0;
                        if (ta == null) return 1;
                        if (tb == null) return -1;
                        return tb.compareTo(ta);
                      });
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _buildTransactionCard(theme, docs[index].data());
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
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Card(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(words: 2),
                  SizedBox(height: 8),
                  Bone.text(words: 3, fontSize: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(ThemeData theme, Map<String, dynamic> tx) {
    final restaurantName = tx['restaurantName'] as String? ?? 'Restaurant';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final paymentMethod = tx['paymentMethod'] as String? ?? 'online';
    final createdAt = tx['createdAt'] as Timestamp?;
    final orderId = tx['orderId'] as String? ?? '';
    final dateStr = createdAt != null
        ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
        : '';

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
              Expanded(child: Text(restaurantName).semiBold()),
              Text(
                formatPkr(amount),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (orderId.isNotEmpty) ...[
                Text('Order #${orderId.substring(0, 6).toUpperCase()}')
                    .muted()
                    .small(),
                const SizedBox(width: 12),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: paymentMethod == 'saved_card'
                      ? Colors.purple.withAlpha(30)
                      : Colors.blue.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  paymentMethod == 'saved_card' ? 'SAVED CARD' : 'ONLINE',
                  style: TextStyle(
                    color: paymentMethod == 'saved_card'
                        ? Colors.purple
                        : Colors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (dateStr.isNotEmpty) Text(dateStr).muted().small(),
            ],
          ),
        ],
      ),
    );
  }
}

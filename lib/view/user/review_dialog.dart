import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/utils/toast_helper.dart';

class _AlreadyReviewedException implements Exception {}

void showReviewDialog(
  BuildContext context, {
  required String restaurantId,
  required String restaurantName,
  required String orderId,
  required String customerId,
  required String customerName,
}) {
  int selectedRating = 0;
  final commentController = TextEditingController();
  bool submitting = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Rate your experience'),
          content: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(restaurantName).semiBold(),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () {
                            setDialogState(() => selectedRating = index + 1);
                          },
                          child: Icon(
                            RadixIcons.star,
                            color: index < selectedRating
                                ? theme.colorScheme.primary
                                : theme.colorScheme.mutedForeground,
                            size: 32,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  const Text('Comment (optional)').semiBold().small(),
                  const SizedBox(height: 6),
                  TextField(
                    controller: commentController,
                    placeholder: const Text('Share your experience...'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            OutlineButton(
              onPressed: submitting
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      Future.microtask(() => commentController.dispose());
                    },
              child: const Text('Cancel'),
            ),
            PrimaryButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (selectedRating < 1) {
                        showAppToast(ctx, 'Please select a rating');
                        return;
                      }
                      setDialogState(() => submitting = true);

                      try {
                        final firestore = FirebaseFirestore.instance;
                        final reviewDocId = '${orderId}_$customerId';
                        final restaurantRef =
                            firestore.collection('restaurants').doc(restaurantId);
                        final reviewRef =
                            restaurantRef.collection('reviews').doc(reviewDocId);
                        final userOrderRef = firestore
                            .collection('users')
                            .doc(customerId)
                            .collection('orders')
                            .doc(orderId);
                        final userSnapshot =
                            await firestore.collection('users').doc(customerId).get();
                        final userData = userSnapshot.data() ?? <String, dynamic>{};
                        final resolvedCustomerName = [
                          userData['username'],
                          userData['name'],
                          userData['fullName'],
                          userData['displayName'],
                          customerName,
                        ]
                            .map((e) => e?.toString().trim() ?? '')
                            .firstWhere((e) => e.isNotEmpty, orElse: () => 'Customer');
                        final resolvedCustomerPhoto = [
                          userData['profileImageUrl'],
                          userData['photoUrl'],
                          userData['avatarUrl'],
                        ]
                            .map((e) => e?.toString().trim() ?? '')
                            .firstWhere((e) => e.isNotEmpty, orElse: () => '');

                        await firestore.runTransaction((txn) async {
                          final existingReview = await txn.get(reviewRef);
                          if (existingReview.exists) {
                            throw _AlreadyReviewedException();
                          }
                          final userOrder = await txn.get(userOrderRef);
                          final alreadyReviewed =
                              (userOrder.data()?['reviewed'] == true);
                          if (alreadyReviewed) {
                            throw _AlreadyReviewedException();
                          }

                          txn.set(reviewRef, {
                            'customerId': customerId,
                            'customerName': resolvedCustomerName,
                            'customerDisplayName': resolvedCustomerName,
                            if (resolvedCustomerPhoto.isNotEmpty)
                              'customerProfileImageUrl': resolvedCustomerPhoto,
                            'rating': selectedRating,
                            'comment': commentController.text.trim(),
                            'orderId': orderId,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          txn.update(userOrderRef, {'reviewed': true});
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        Future.microtask(() => commentController.dispose());
                        if (context.mounted) {
                          showAppToast(context, 'Review submitted');
                        }
                      } on _AlreadyReviewedException {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(customerId)
                            .collection('orders')
                            .doc(orderId)
                            .update({'reviewed': true});
                        if (ctx.mounted) Navigator.pop(ctx);
                        Future.microtask(() => commentController.dispose());
                        if (context.mounted) {
                          showAppToast(context, 'Review already submitted');
                        }
                      } catch (e) {
                        debugPrint('[ReviewDialog] Error: $e');
                        setDialogState(() => submitting = false);
                        if (ctx.mounted) {
                          showAppToast(
                              ctx, 'Something went wrong. Please try again.');
                        }
                      }
                    },
              child: submitting
                  ? const Text('Submitting...')
                  : const Text('Submit'),
            ),
          ],
        );
      },
    ),
  );
}

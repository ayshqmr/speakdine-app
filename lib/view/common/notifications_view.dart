import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speak_dine/services/notification_service.dart';
import 'package:speak_dine/widgets/customer_voice_fab.dart';

/// Full-screen notifications. Realtime Firestore updates are used for
/// [NotificationsView.restaurant] only; customer uses a static explainer (no listener).
class NotificationsView extends StatefulWidget {
  const NotificationsView.restaurant({super.key}) : _restaurantRealtime = true;
  const NotificationsView.customer({super.key}) : _restaurantRealtime = false;

  final bool _restaurantRealtime;

  bool get restaurantRealtime => _restaurantRealtime;

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.primary,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton.filledTonal(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: widget.restaurantRealtime
                ? _RestaurantNotificationsBody(theme: theme)
                : _CustomerNotificationsPlaceholder(theme: theme),
          ),
          if (!widget.restaurantRealtime)
            const CustomerVoiceFabPositioned(hasBottomDock: false),
        ],
      ),
    );
  }
}

class _CustomerNotificationsPlaceholder extends StatelessWidget {
  final ThemeData theme;

  const _CustomerNotificationsPlaceholder({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 100,
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 24),
          Text(
            'Order updates',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Track your orders under My Orders. Live alerts are available in the restaurant app for merchants.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ).animate().fadeIn(),
    );
  }
}

class _RestaurantNotificationsBody extends StatelessWidget {
  final ThemeData theme;

  const _RestaurantNotificationsBody({required this.theme});

  static String _timeAgo(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  (IconData icon, Color color) _iconFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('deliver')) {
      return (Icons.check_circle_rounded, Colors.green);
    }
    if (t.contains('pick') || t.contains('rider')) {
      return (Icons.delivery_dining_rounded, Colors.deepPurple);
    }
    if (t.contains('accept')) {
      return (Icons.thumb_up_rounded, Colors.teal);
    }
    if (t.contains('order') || t.contains('new')) {
      return (Icons.shopping_bag_rounded, Colors.blue);
    }
    return (Icons.notifications_rounded, theme.colorScheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Text(
          'Sign in to see notifications',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: NotificationService.getNotifications(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load notifications',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 100,
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 24),
                Text(
                  'No notifications',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ).animate().fadeIn(),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final title = data['title'] as String? ?? '';
            final message = data['message'] as String? ?? '';
            final read = data['read'] as bool? ?? false;
            final createdAt = data['createdAt'] as Timestamp?;
            final (icon, iconColor) = _iconFor(title);

            return GestureDetector(
              onTap: read
                  ? null
                  : () => NotificationService.markAsRead(user.uid, doc.id),
              child: _NotificationCard(
                theme: theme,
                title: title,
                body: message,
                time: _timeAgo(createdAt?.toDate()),
                icon: icon,
                iconColor: iconColor,
                read: read,
              ),
            )
                .animate(delay: (index * 100).ms)
                .fadeIn()
                .slideX(begin: 0.1);
          },
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String body;
  final String time;
  final IconData icon;
  final Color iconColor;
  final bool read;

  const _NotificationCard({
    required this.theme,
    required this.title,
    required this.body,
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.read,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: read
            ? theme.colorScheme.surface
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: read
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
              : theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: read ? FontWeight.w700 : FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

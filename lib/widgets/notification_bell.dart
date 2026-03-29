import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/services/notification_service.dart';

/// Customer home bell: loads unread count once (no Firestore snapshot listener).
/// Tap opens a list loaded on demand; pull-to-refresh is omitted for simplicity.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int? _unread;
  bool _loadingUnread = false;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _loadingUnread = true;
    });
    try {
      final n = await NotificationService.fetchUnreadCount(user.uid);
      if (mounted) {
        setState(() {
          _unread = n;
          _loadingUnread = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unread = null;
          _loadingUnread = false;
        });
      }
    }
  }

  Future<void> _openNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await showDialog(
      context: context,
      builder: (ctx) => _NotificationListDialog(userId: user.uid),
    );
    if (mounted) _loadUnread();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Icon(
        RadixIcons.bell,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    final currentTheme = Theme.of(context);
    final count = _unread ?? 0;
    return GestureDetector(
      onTap: _openNotifications,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            RadixIcons.bell,
            size: 20,
            color: currentTheme.colorScheme.primary,
          ),
          if (count > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: currentTheme.colorScheme.destructive,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    color: currentTheme.colorScheme.background,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_loadingUnread && _unread == null)
            Positioned(
              right: -4,
              top: -4,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: currentTheme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationListDialog extends StatelessWidget {
  final String userId;

  const _NotificationListDialog({required this.userId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Notifications'),
          FutureBuilder<int>(
            future: NotificationService.fetchUnreadCount(userId),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              if (unreadCount == 0) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () {
                  NotificationService.markAllAsRead(userId);
                },
                child: Text(
                  'Mark all as read',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        height: 400,
        child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('notifications')
              .doc(userId)
              .collection('items')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Failed to load notifications',
                  style: TextStyle(color: theme.colorScheme.destructive),
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
                      RadixIcons.bell,
                      size: 48,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No notifications yet',
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final title = data['title'] as String? ?? '';
                final message = data['message'] as String? ?? '';
                final read = data['read'] as bool? ?? false;
                final createdAt = data['createdAt'] as Timestamp?;

                return _NotificationTile(
                  id: doc.id,
                  userId: userId,
                  title: title,
                  message: message,
                  read: read,
                  createdAt: createdAt?.toDate(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final String id;
  final String userId;
  final String title;
  final String message;
  final bool read;
  final DateTime? createdAt;

  const _NotificationTile({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.read,
    required this.createdAt,
  });

  String _timeAgo(DateTime? date) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: read ? null : () => NotificationService.markAsRead(userId, id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!read)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: read ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

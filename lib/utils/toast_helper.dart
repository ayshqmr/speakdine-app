import 'package:shadcn_flutter/shadcn_flutter.dart';

void showAppToast(BuildContext context, String message) {
  final theme = Theme.of(context);
  showToast(
    context: context,
    builder: (context, overlay) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(RadixIcons.infoCircled, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    },
    location: ToastLocation.topCenter,
    showDuration: const Duration(seconds: 4),
  );
}

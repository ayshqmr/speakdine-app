import 'package:shadcn_flutter/shadcn_flutter.dart';

void showAppToast(BuildContext context, String message, {bool isError = false}) {
  final theme = Theme.of(context);

  showToast(
    context: context,
    builder: (context, overlay) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isError ? theme.colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: isError
              ? null
              : Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? RadixIcons.crossCircled : RadixIcons.checkCircled,
              color: isError ? Colors.white : theme.colorScheme.primary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  color: isError ? Colors.white : theme.colorScheme.primary,
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

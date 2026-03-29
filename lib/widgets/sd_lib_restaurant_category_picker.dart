import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';

/// SD-lib single-select chips for restaurant type (`restaurantCategory` in Firestore).
class SdLibRestaurantCategoryPicker extends StatelessWidget {
  const SdLibRestaurantCategoryPicker({
    super.key,
    required this.theme,
    required this.selectedId,
    required this.onChanged,
    this.dense = false,
  });

  final ThemeData theme;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Restaurant category',
          style: TextStyle(
            color: theme.colorScheme.foreground,
            fontWeight: FontWeight.w700,
            fontSize: dense ? 12 : 13,
          ),
        ),
        SizedBox(height: dense ? 4 : 4),
        Text(
          'Pick one venue type (e.g. Desi, Fast Food). Menu dishes do not need their own category.',
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: dense ? 10 : 11,
          ),
        ),
        SizedBox(height: dense ? 8 : 10),
        Wrap(
          spacing: dense ? 6 : 8,
          runSpacing: dense ? 6 : 8,
          children: kSdLibRestaurantCategories.map((c) {
            final selected = selectedId == c.id;
            return GestureDetector(
              onTap: () => onChanged(c.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 8 : 10,
                  vertical: dense ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.border.withValues(alpha: 0.4),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: dense ? 10 : 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.mutedForeground,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

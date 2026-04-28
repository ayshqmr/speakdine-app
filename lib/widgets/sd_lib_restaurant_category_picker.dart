import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';

/// SD-lib single-select dropdown for restaurant type (`restaurantCategory` in Firestore).
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
    final m = material.Theme.of(context);
    final knownIds = kSdLibRestaurantCategories.map((c) => c.id).toSet();
    final effectiveValue =
        selectedId != null && knownIds.contains(selectedId) ? selectedId : null;
    final hintStyle = TextStyle(
      color: theme.colorScheme.foreground.withValues(alpha: 0.62),
      fontSize: dense ? 13 : 14,
      fontWeight: FontWeight.w500,
    );
    final itemStyle = TextStyle(
      color: theme.colorScheme.foreground,
      fontSize: dense ? 13 : 15,
      fontWeight: FontWeight.w600,
    );

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
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.muted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.28),
              width: 1,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 10 : 12,
            vertical: dense ? 2 : 4,
          ),
          child: material.DropdownButtonHideUnderline(
            child: material.DropdownButton<String>(
              value: effectiveValue,
              hint: Text('Select a category', style: hintStyle),
              isExpanded: true,
              padding: EdgeInsets.zero,
              icon: Icon(
                RadixIcons.chevronDown,
                size: dense ? 20 : 22,
                color: theme.colorScheme.primary,
              ),
              style: itemStyle,
              dropdownColor: m.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              items: kSdLibRestaurantCategories
                  .map(
                    (c) => material.DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(
                        c.label,
                        style: itemStyle.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) onChanged(id);
              },
            ),
          ),
        ),
      ],
    );
  }
}

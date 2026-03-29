import 'package:flutter/material.dart' as material
    show Colors, ScrollViewKeyboardDismissBehavior, showModalBottomSheet;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';

/// SD-lib filter state for the customer restaurant explore screen.
class SdLibRestaurantExploreFilters {
  const SdLibRestaurantExploreFilters({
    this.categoryId,
    this.openNowOnly = false,
  });

  /// `null` means all categories.
  final String? categoryId;
  final bool openNowOnly;

  int get activeCount =>
      (categoryId != null ? 1 : 0) + (openNowOnly ? 1 : 0);

  bool get hasActiveFilters => activeCount > 0;
}

/// Inline category chips + “Open now” under the search bar (same state as sheet).
class SdLibRestaurantFilterStrip extends StatelessWidget {
  const SdLibRestaurantFilterStrip({
    super.key,
    required this.theme,
    required this.filters,
    required this.onChanged,
  });

  final ThemeData theme;
  final SdLibRestaurantExploreFilters filters;
  final ValueChanged<SdLibRestaurantExploreFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final selectedId = filters.categoryId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedId != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SdLibExploreCategoryChip(
              theme: t,
              label: sdLibRestaurantCategoryLabel(selectedId) ?? selectedId,
              categoryId: selectedId,
              selectedCategoryId: selectedId,
              onTap: () => onChanged(
                SdLibRestaurantExploreFilters(
                  categoryId: null,
                  openNowOnly: filters.openNowOnly,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: t.colorScheme.muted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: t.colorScheme.border.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                RadixIcons.clock,
                size: 18,
                color: t.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Open now').semiBold().small(),
                    const SizedBox(height: 2),
                    const Text('Only show places open right now')
                        .muted()
                        .small(),
                  ],
                ),
              ),
              Switch(
                value: filters.openNowOnly,
                onChanged: (v) => onChanged(
                  SdLibRestaurantExploreFilters(
                    categoryId: filters.categoryId,
                    openNowOnly: v,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One category chip; shared by [SdLibRestaurantFilterStrip] and the filter sheet.
class SdLibExploreCategoryChip extends StatelessWidget {
  const SdLibExploreCategoryChip({
    super.key,
    required this.theme,
    required this.label,
    required this.categoryId,
    required this.selectedCategoryId,
    required this.onTap,
  });

  final ThemeData theme;
  final String label;
  final String? categoryId;
  final String? selectedCategoryId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final selected = selectedCategoryId == categoryId;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? t.colorScheme.primary.withValues(alpha: 0.15)
              : t.colorScheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? t.colorScheme.primary
                : t.colorScheme.border.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? t.colorScheme.primary
                : t.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// SD-lib search row: muted field + filter affordance with optional badge.
class SdLibRestaurantSearchFilterBar extends StatefulWidget {
  const SdLibRestaurantSearchFilterBar({
    super.key,
    required this.controller,
    required this.theme,
    required this.onQueryChanged,
    required this.onOpenFilters,
    required this.activeFilterCount,
  });

  final TextEditingController controller;
  final ThemeData theme;
  final VoidCallback onQueryChanged;
  final VoidCallback onOpenFilters;
  final int activeFilterCount;

  @override
  State<SdLibRestaurantSearchFilterBar> createState() =>
      _SdLibRestaurantSearchFilterBarState();
}

class _SdLibRestaurantSearchFilterBarState
    extends State<SdLibRestaurantSearchFilterBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant SdLibRestaurantSearchFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  /// Drive filter UI from the same controller (typing + voice). Parent [onQueryChanged]
  /// rebuilds this bar — do not call [setState] here: double rebuilds + layout jump when
  /// the clear button appears caused the field to lose focus after one character.
  void _onText() => widget.onQueryChanged();

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: t.colorScheme.muted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: t.colorScheme.border.withValues(alpha: 0.35),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    RadixIcons.magnifyingGlass,
                    size: 18,
                    color: t.colorScheme.mutedForeground,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    placeholder: const Text('Search by name or address'),
                  ),
                ),
                // Fixed width so showing the clear control does not resize the field / steal focus.
                SizedBox(
                  width: 44,
                  child: widget.controller.text.isNotEmpty
                      ? GhostButton(
                          density: ButtonDensity.icon,
                          onPressed: () {
                            widget.controller.clear();
                            widget.onQueryChanged();
                          },
                          child: Icon(
                            RadixIcons.cross2,
                            size: 16,
                            color: t.colorScheme.mutedForeground,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            OutlineButton(
              density: ButtonDensity.icon,
              onPressed: widget.onOpenFilters,
              child: Icon(
                RadixIcons.slider,
                size: 18,
                color: t.colorScheme.primary,
              ),
            ),
            if (widget.activeFilterCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: t.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '${widget.activeFilterCount}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.colorScheme.primaryForeground,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// SD-lib bottom sheet: category chips + “Open now” toggle.
Future<SdLibRestaurantExploreFilters?> showSdLibRestaurantFilterSheet(
  BuildContext context, {
  required ThemeData theme,
  required SdLibRestaurantExploreFilters initial,
}) {
  return material.showModalBottomSheet<SdLibRestaurantExploreFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: material.Colors.transparent,
    builder: (ctx) {
      return _SdLibFilterSheetBody(
        theme: theme,
        initial: initial,
      );
    },
  );
}

class _SdLibFilterSheetBody extends StatefulWidget {
  const _SdLibFilterSheetBody({
    required this.theme,
    required this.initial,
  });

  final ThemeData theme;
  final SdLibRestaurantExploreFilters initial;

  @override
  State<_SdLibFilterSheetBody> createState() => _SdLibFilterSheetBodyState();
}

class _SdLibFilterSheetBodyState extends State<_SdLibFilterSheetBody> {
  late String? _categoryId;
  late bool _openNowOnly;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initial.categoryId;
    _openNowOnly = widget.initial.openNowOnly;
  }

  void _reset() {
    setState(() {
      _categoryId = null;
      _openNowOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: t.colorScheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(
            color: t.colorScheme.border.withValues(alpha: 0.25),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                material.ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.colorScheme.border.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(RadixIcons.slider, size: 18, color: t.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Filters').h4().semiBold(),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Narrow restaurants by type and hours.')
                    .muted()
                    .small(),
                const SizedBox(height: 20),
                const Text('Category').semiBold().small(),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SdLibExploreCategoryChip(
                      theme: t,
                      label: 'All',
                      categoryId: null,
                      selectedCategoryId: _categoryId,
                      onTap: () => setState(() => _categoryId = null),
                    ),
                    ...kSdLibRestaurantCategories.map(
                      (c) => SdLibExploreCategoryChip(
                        theme: t,
                        label: c.label,
                        categoryId: c.id,
                        selectedCategoryId: _categoryId,
                        onTap: () => setState(() => _categoryId = c.id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.colorScheme.muted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: t.colorScheme.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        RadixIcons.clock,
                        size: 18,
                        color: t.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Open now').semiBold().small(),
                            const SizedBox(height: 2),
                            const Text('Only show places open right now')
                                .muted()
                                .small(),
                          ],
                        ),
                      ),
                      Switch(
                        value: _openNowOnly,
                        onChanged: (v) => setState(() => _openNowOnly = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlineButton(
                        onPressed: _reset,
                        child: const Text('Clear all'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            SdLibRestaurantExploreFilters(
                              categoryId: _categoryId,
                              openNowOnly: _openNowOnly,
                            ),
                          );
                        },
                        child: const Text('Apply filters'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

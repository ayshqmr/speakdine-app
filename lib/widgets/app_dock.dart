import 'package:shadcn_flutter/shadcn_flutter.dart';

class DockItem {
  final IconData icon;
  final String label;

  const DockItem({required this.icon, required this.label});
}

class AppDock extends StatelessWidget {
  final List<DockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Widget? badge;
  final int? badgeIndex;

  const AppDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.badge,
    this.badgeIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 16),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = index == selectedIndex;

          return GestureDetector(
            onTap: () => onTap(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _buildIcon(index, item, isSelected, theme),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildIcon(
      int index, DockItem item, bool isSelected, ThemeData theme) {
    final icon = Icon(
      item.icon,
      size: 22,
      color: isSelected
          ? theme.colorScheme.primary
          : Colors.white.withValues(alpha: 0.85),
    );

    if (badgeIndex == index && badge != null && !isSelected) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(right: -6, top: -6, child: badge!),
        ],
      );
    }

    return icon;
  }
}

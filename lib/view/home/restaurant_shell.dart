import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/widgets/app_dock.dart';
import 'package:speak_dine/view/restaurant/restaurant_dashboard_view.dart';
import 'package:speak_dine/view/restaurant/menu_management.dart';
import 'package:speak_dine/view/restaurant/orders_view.dart';
import 'package:speak_dine/view/restaurant/restaurant_profile.dart';
import 'package:speak_dine/view/restaurant/restaurant_transactions_view.dart';
import 'package:speak_dine/widgets/keyboard_friendly.dart';

const _restaurantDockItems = [
  DockItem(icon: RadixIcons.home, label: 'Home'),
  DockItem(icon: RadixIcons.reader, label: 'Menu'),
  DockItem(icon: RadixIcons.archive, label: 'Orders'),
  DockItem(icon: RadixIcons.cardStack, label: 'Payments'),
  DockItem(icon: RadixIcons.person, label: 'Profile'),
];

class RestaurantShell extends StatefulWidget {
  const RestaurantShell({super.key});

  @override
  State<RestaurantShell> createState() => _RestaurantShellState();
}

class _RestaurantShellState extends State<RestaurantShell> {
  int _selectedIndex = 0;
  bool _pendingOpenMenuAdd = false;

  void _goToTab(int index) {
    if (index < 0 || index >= _restaurantDockItems.length) return;
    setState(() => _selectedIndex = index);
  }

  void _goToMenuAndAddDish() {
    setState(() {
      _pendingOpenMenuAdd = true;
      _selectedIndex = 1;
    });
  }

  void _clearPendingMenuAdd() {
    if (_pendingOpenMenuAdd) {
      setState(() => _pendingOpenMenuAdd = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      child: Container(
        color: theme.colorScheme.background,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: RestoreKeyboardViewInsets(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      RestaurantDashboardView(
                        onNavigateToTab: _goToTab,
                        onNavigateToMenuAndAddDish: _goToMenuAndAddDish,
                      ),
                      MenuManagementView(
                        openAddDialogAfterBuild: _pendingOpenMenuAdd,
                        onConsumedOpenAdd: _clearPendingMenuAdd,
                      ),
                      const OrdersView(),
                      const RestaurantTransactionsView(),
                      const RestaurantProfileView(),
                    ],
                  ),
                ),
              ),
              AppDock(
                items: _restaurantDockItems,
                selectedIndex: _selectedIndex,
                onTap: _goToTab,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

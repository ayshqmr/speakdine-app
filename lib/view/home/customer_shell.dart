import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' show Icons, MaterialPageRoute;
import 'package:speak_dine/widgets/app_dock.dart';
import 'package:speak_dine/view/home/user_home.dart';
import 'package:speak_dine/view/user/cart_view.dart';
import 'package:speak_dine/view/user/customer_orders_view.dart';
import 'package:speak_dine/view/user/customer_profile.dart';
import 'package:speak_dine/view/user/customer_transactions_view.dart';
import 'package:speak_dine/services/cart_service.dart';

final _customerDockItems = [
  const DockItem(icon: RadixIcons.home, label: 'Restaurants'),
  DockItem(icon: Icons.shopping_bag_outlined, label: 'Cart'),
  const DockItem(icon: RadixIcons.archive, label: 'Orders'),
  const DockItem(icon: RadixIcons.cardStack, label: 'Payments'),
  const DockItem(icon: RadixIcons.person, label: 'Profile'),
];

const _cartTabIndex = 1;

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _selectedIndex = 0;
  final _restaurantsNavKey = GlobalKey<NavigatorState>();

  void _onDockTap(int index) {
    if (index == _selectedIndex && index == 0) {
      _restaurantsNavKey.currentState?.popUntil((route) => route.isFirst);
    }
    setState(() => _selectedIndex = index);
  }

  void _switchToCart() {
    setState(() => _selectedIndex = _cartTabIndex);
  }

  void _switchToPayments() {
    setState(() => _selectedIndex = 3);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cartCount = cartService.totalItems;

    return Scaffold(
      child: Container(
        color: theme.colorScheme.background,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    Navigator(
                      key: _restaurantsNavKey,
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (_) => UserHomeView(
                          onCartChanged: () => setState(() {}),
                          onViewCart: _switchToCart,
                          onViewPayments: _switchToPayments,
                        ),
                      ),
                    ),
                    CartView(
                      embedded: true,
                      onOrderPlaced: _switchToPayments,
                    ),
                    const CustomerOrdersView(),
                    const CustomerTransactionsView(),
                    const CustomerProfileView(),
                  ],
                ),
              ),
              AppDock(
                items: _customerDockItems,
                selectedIndex: _selectedIndex,
                onTap: _onDockTap,
                badgeIndex: _cartTabIndex,
                badge: cartCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.destructive,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$cartCount',
                          style: TextStyle(
                            color: theme.colorScheme.background,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

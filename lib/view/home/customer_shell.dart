import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/widgets/app_dock.dart';
import 'package:speak_dine/view/home/user_home.dart';
import 'package:speak_dine/view/user/cart_view.dart';
import 'package:speak_dine/view/user/customer_orders_view.dart';
import 'package:speak_dine/view/user/customer_profile.dart';
import 'package:speak_dine/view/user/customer_transactions_view.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/voice/voice_assistant_session.dart';
import 'package:speak_dine/widgets/keyboard_friendly.dart';
import 'package:speak_dine/widgets/voice_assistant_sheet.dart';

final _customerDockItems = [
  const DockItem(icon: RadixIcons.home, label: 'Restaurants'),
  DockItem(icon: Icons.shopping_bag, label: 'Cart'),
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
  late final VoiceAssistantSession _voiceSession;

  @override
  void initState() {
    super.initState();
    _voiceSession = VoiceAssistantSession(
      switchToTab: _switchCustomerTab,
      onMicNotReady: () {
        if (!mounted) return;
        showAppToast(
          context,
          'Speech recognition is not available on this device.',
        );
      },
      onCouldNotStartListening: () {
        if (!mounted) return;
        showAppToast(
          context,
          'Could not start the microphone. Check permissions.',
        );
      },
    );
  }

  @override
  void dispose() {
    _voiceSession.dispose();
    super.dispose();
  }

  void _onDockTap(int index) {
    if (index == _selectedIndex && index == 0) {
      _restaurantsNavKey.currentState?.popUntil((route) => route.isFirst);
    }
    setState(() => _selectedIndex = index);
  }

  void _switchToCart() {
    setState(() => _selectedIndex = _cartTabIndex);
  }

  void _switchCustomerTab(int index) => _onDockTap(index);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cartCount = cartService.totalItems;

    return Scaffold(
      child: Container(
        color: theme.colorScheme.background,
        child: SafeArea(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                children: [
                  Expanded(
                    child: RestoreKeyboardViewInsets(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          Navigator(
                            key: _restaurantsNavKey,
                            onGenerateRoute: (_) => MaterialPageRoute(
                              builder: (_) => UserHomeView(
                                onCartChanged: () => setState(() {}),
                                onViewCart: _switchToCart,
                              ),
                            ),
                          ),
                          CartView(embedded: true),
                          const CustomerOrdersView(),
                          const CustomerTransactionsView(),
                          const CustomerProfileView(),
                        ],
                      ),
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
                              color: theme.colorScheme.background,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$cartCount',
                              style: TextStyle(
                                color: theme.colorScheme.destructive,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
              Positioned(
                right: 8,
                bottom: 88,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GhostButton(
                      density: ButtonDensity.icon,
                      onPressed: () => showVoiceAssistantSheet(context),
                      child: Icon(
                        RadixIcons.questionMarkCircled,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {
                        _voiceSession.onHoldStart();
                      },
                      onPointerUp: (_) {
                        _voiceSession.onHoldEnd();
                      },
                      onPointerCancel: (_) {
                        _voiceSession.onHoldEnd();
                      },
                      child: ValueListenableBuilder<bool>(
                        valueListenable:
                            CustomerVoiceBridge.instance.voiceListening,
                        builder: (context, listening, _) {
                          return buildVoiceFab(
                            theme,
                            listening: listening,
                            onPressed: () {},
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

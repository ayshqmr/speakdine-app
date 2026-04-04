import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/services/login_lookup_sync.dart';
import 'package:speak_dine/utils/customer_username_validation.dart';
import 'package:speak_dine/widgets/app_dock.dart';
import 'package:speak_dine/view/home/user_home.dart';
import 'package:speak_dine/view/user/cart_view.dart';
import 'package:speak_dine/view/user/customer_orders_view.dart';
import 'package:speak_dine/view/user/order_tracking_view.dart';
import 'package:speak_dine/voice/order_tracking_voice_summary.dart';
import 'package:speak_dine/voice/voice_intent_router.dart';
import 'package:speak_dine/view/user/customer_profile.dart';
import 'package:speak_dine/view/user/customer_transactions_view.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/voice/voice_assistant_session.dart';
import 'package:speak_dine/widgets/keyboard_friendly.dart';
import 'package:speak_dine/widgets/customer_voice_fab.dart';

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
  bool _welcomeSpoken = false;

  late final String Function() _voiceLlmContextSnapshot = _buildVoiceLlmContext;

  @override
  void initState() {
    super.initState();
    CustomerVoiceBridge.instance.updateCustomerDisplayName =
        _voiceUpdateCustomerDisplayName;
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
    CustomerVoiceBridge.instance.notifyCartChanged = _onVoiceCartChanged;
    CustomerVoiceBridge.instance.voiceMicHoldStart = () {
      _voiceSession.onHoldStart();
    };
    CustomerVoiceBridge.instance.voiceMicHoldEnd = () {
      _voiceSession.onHoldEnd();
    };
    CustomerVoiceBridge.instance.playRestaurantDetailVoiceIntro =
        _voiceSession.playRestaurantDetailVoiceIntro;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && cartService.isEmpty) {
        await cartService.restoreForCustomer(user.uid);
        if (mounted) setState(() {});
      }
      if (!mounted || _welcomeSpoken) {
        return;
      }
      _welcomeSpoken = true;
      await _voiceSession.playSpeaktimeWelcomeOnce();
    });
  }

  String _buildVoiceLlmContext() {
    final b = CustomerVoiceBridge.instance;
    const tabNames = ['Restaurants', 'Cart', 'Orders', 'Payments', 'Profile'];
    final sb = StringBuffer();
    sb.writeln('Selected tab: ${tabNames[_selectedIndex]}.');
    if (_selectedIndex == 0) {
      final canPop = _restaurantsNavKey.currentState?.canPop() ?? false;
      sb.writeln(
        canPop
            ? 'User is viewing a restaurant menu (opened from browse).'
            : 'User is on the restaurant browse and search list.',
      );
    }
    sb.writeln(_cartVoiceSummaryForLlm());
    final profile = b.restaurantVoiceProfileSummary;
    if (profile != null && profile.trim().isNotEmpty) {
      sb.writeln(profile.trim());
    }
    final menu = b.restaurantMenuVoiceSummary;
    if (menu != null && menu.trim().isNotEmpty) {
      sb.writeln(menu.trim());
    }
    final reviews = b.restaurantVoiceReviewsSummary;
    if (reviews != null && reviews.trim().isNotEmpty) {
      sb.writeln('Reviews (read verbatim when user asks about reviews):\n${reviews.trim()}');
    }
    return sb.toString();
  }

  String _cartVoiceSummaryForLlm() {
    if (cartService.isEmpty) {
      return 'Shopping cart is empty.';
    }
    final parts = <String>[];
    cartService.cart.forEach((_, items) {
      for (final it in items) {
        final q = it['quantity'] ?? 1;
        final n = it['name'] ?? 'item';
        parts.add('$q times $n');
      }
    });
    return 'Shopping cart contains: ${parts.join(', ')}.';
  }

  void _onVoiceCartChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (CustomerVoiceBridge.instance.updateCustomerDisplayName ==
        _voiceUpdateCustomerDisplayName) {
      CustomerVoiceBridge.instance.updateCustomerDisplayName = null;
    }
    if (CustomerVoiceBridge.instance.notifyCartChanged == _onVoiceCartChanged) {
      CustomerVoiceBridge.instance.notifyCartChanged = null;
    }
    if (CustomerVoiceBridge.instance.buildVoiceAssistantContextForLlm ==
        _voiceLlmContextSnapshot) {
      CustomerVoiceBridge.instance.buildVoiceAssistantContextForLlm = null;
    }
    if (CustomerVoiceBridge.instance.openActiveOrderTracking ==
        _openActiveOrderTracking) {
      CustomerVoiceBridge.instance.openActiveOrderTracking = null;
    }
    CustomerVoiceBridge.instance.voiceMicHoldStart = null;
    CustomerVoiceBridge.instance.voiceMicHoldEnd = null;
    CustomerVoiceBridge.instance.playRestaurantDetailVoiceIntro = null;
    _voiceSession.dispose();
    super.dispose();
  }

  Future<String?> _voiceUpdateCustomerDisplayName(String spokenNewName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'Please sign in to change your name.';
    }

    final normalized = normalizeCustomerUsernameFromSpeech(spokenNewName);
    if (normalized.isEmpty) {
      return 'Use letters, numbers, or symbols in your username. '
          'For example, alex or alex_12.';
    }

    final formatErr = validateCustomerUsernameFormat(normalized);
    if (formatErr != null) return formatErr;

    final firestore = FirebaseFirestore.instance;
    final snap = await firestore.collection('users').doc(user.uid).get();
    if (!snap.exists) {
      return 'Profile not found. Open Profile and try again.';
    }
    final data = snap.data()!;
    final email = (data['email'] as String?)?.trim() ?? user.email ?? '';
    final previousName = (data['name'] as String?)?.trim() ?? '';

    final lookupRes = await LoginLookupSync.syncCustomerDisplayName(
      firestore: firestore,
      uid: user.uid,
      email: email,
      previousName: previousName.isEmpty ? null : previousName,
      newName: normalized,
    );
    if (lookupRes == LoginLookupSyncResult.nameAlreadyClaimed) {
      return 'That username is already taken. Try another.';
    }
    if (lookupRes == LoginLookupSyncResult.failed) {
      return 'Could not update your username. Check your connection.';
    }

    try {
      await firestore.collection('users').doc(user.uid).update({
        'name': normalized,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint('[CustomerShell] voice name update: $e $st');
      return 'Could not save. Try again in Profile.';
    }

    if (mounted) {
      showAppToast(context, 'Name updated');
    }
    return null;
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

  Future<String?> _openActiveOrderTracking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'Please sign in to track your order.';
    }
    try {
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('orders')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();
      const active = {
        'pending',
        'accepted',
        'in_kitchen',
        'handed_to_rider',
        'on_the_way',
      };
      for (final doc in qs.docs) {
        final data = doc.data();
        final s = (data['status'] as String? ?? '').trim();
        if (!active.contains(s)) continue;
        final name = (data['restaurantName'] ?? 'Restaurant').toString();
        if (!mounted) return null;
        setState(() => _selectedIndex = VoiceIntentRouter.tabOrders);
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                OrderTrackingView(orderId: doc.id, restaurantName: name),
          ),
        );
        return buildOrderTrackingVoiceSummary(data);
      }
    } catch (e, st) {
      debugPrint('[CustomerShell] track order: $e\n$st');
      return 'Could not load your orders. Check your connection and try again.';
    }
    return 'You have no active order to track right now. Open My Orders to see your history.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cartCount = cartService.totalItems;

    final bridge = CustomerVoiceBridge.instance;
    bridge.shellContext = context;
    bridge.popRestaurantRoute = () {
      _restaurantsNavKey.currentState?.maybePop();
    };
    bridge.resetRestaurantStack = () {
      _restaurantsNavKey.currentState?.popUntil((route) => route.isFirst);
    };
    bridge.describeVoiceLocation = () {
      const names = ['Restaurants', 'Cart', 'Orders', 'Payments', 'Profile'];
      return 'You are on the ${names[_selectedIndex]} tab in SpeakDine.';
    };
    bridge.buildVoiceAssistantContextForLlm = _voiceLlmContextSnapshot;
    bridge.openActiveOrderTracking = _openActiveOrderTracking;

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
              const CustomerVoiceFabPositioned(hasBottomDock: true),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart'
    show InkWell, MaterialPageRoute, showModalBottomSheet;
import 'package:skeletonizer/skeletonizer.dart';
import 'package:speak_dine/utils/customer_username_validation.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/widgets/location_picker.dart';
import 'package:speak_dine/services/image_upload_service.dart';
import 'package:speak_dine/services/login_lookup_sync.dart';
import 'package:speak_dine/services/payment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speak_dine/view/authScreens/login_view.dart';
import 'package:speak_dine/view/user/customer_orders_view.dart';
import 'package:speak_dine/view/common/notifications_view.dart';
import 'package:speak_dine/view/common/settings_view.dart';
import 'package:speak_dine/view/common/help_support_view.dart';
import 'package:speak_dine/services/cart_service.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/widgets/customer_voice_fab.dart';

class CustomerProfileView extends StatefulWidget {
  const CustomerProfileView({super.key});

  @override
  State<CustomerProfileView> createState() => _CustomerProfileViewState();
}

class _CustomerProfileViewState extends State<CustomerProfileView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _user = FirebaseAuth.instance.currentUser;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _loadingCards = false;
  double? _lat;
  double? _lng;
  String _address = '';
  String? _photoUrl;
  /// Name last reflected in `loginLookup` (for rename sync).
  String? _loginLookupDisplayName;
  String? _stripeCustomerId;
  List<SavedCard> _savedCards = [];

  void _voiceOpenEditProfile() {
    if (mounted) {
      _openEditProfileSheet();
    }
  }

  void _voiceOpenPaymentsPage() {
    if (!mounted) {
      return;
    }
    final theme = Theme.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CustomerPaymentsPage(
          title: 'Payments & Cards',
          child: _buildSavedCardsSection(theme),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    final b = CustomerVoiceBridge.instance;
    b.openCustomerEditProfile = _voiceOpenEditProfile;
    b.pickCustomerProfilePhoto = _pickAndUploadPhoto;
    b.openCustomerAddressPicker = _openLocationPicker;
    b.openCustomerPaymentsPage = _voiceOpenPaymentsPage;
  }

  @override
  void dispose() {
    final b = CustomerVoiceBridge.instance;
    if (b.openCustomerEditProfile == _voiceOpenEditProfile) {
      b.openCustomerEditProfile = null;
    }
    if (b.pickCustomerProfilePhoto == _pickAndUploadPhoto) {
      b.pickCustomerProfilePhoto = null;
    }
    if (b.openCustomerAddressPicker == _openLocationPicker) {
      b.openCustomerAddressPicker = null;
    }
    if (b.openCustomerPaymentsPage == _voiceOpenPaymentsPage) {
      b.openCustomerPaymentsPage = null;
    }
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final doc =
          await _firestore.collection('users').doc(_user?.uid).get();
      if (doc.exists) {
        final profile = doc.data()!;
        _nameController.text = profile['name'] ?? '';
        _emailController.text = profile['email'] ?? _user?.email ?? '';
        _phoneController.text = profile['phone'] ?? '';
        _lat = (profile['lat'] as num?)?.toDouble();
        _lng = (profile['lng'] as num?)?.toDouble();
        _address = profile['address'] ?? '';
        _cityController.text = profile['city'] ?? '';
        _photoUrl = profile['photoUrl'] as String?;
        _stripeCustomerId = profile['stripeCustomerId'] as String?;
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    if (mounted) setState(() => _loading = false);
    _loadSavedCards();
  }

  Future<void> _loadSavedCards() async {
    if (_stripeCustomerId == null || _stripeCustomerId!.isEmpty) return;
    setState(() => _loadingCards = true);
    final cards = await PaymentService.getSavedCards(
        stripeCustomerId: _stripeCustomerId!);
    if (mounted) {
      setState(() {
        _savedCards = cards;
        _loadingCards = false;
      });
    }
  }

  Future<void> _addCard() async {
    final customerId = _stripeCustomerId ??
        await PaymentService.ensureStripeCustomer(
          userId: _user?.uid ?? '',
          email: _emailController.text.trim(),
          name: _nameController.text.trim(),
        );

    if (customerId == null) {
      if (mounted) showAppToast(context, 'Could not set up payment. Try again.');
      return;
    }

    _stripeCustomerId = customerId;

    final opened = await PaymentService.openCardSetup(
        stripeCustomerId: customerId);
    if (opened && mounted) {
      showAppToast(context, 'Complete card setup in the opened page, then return here.');
    }
  }

  Future<void> _deleteCard(SavedCard card) async {
    final deleted =
        await PaymentService.deleteSavedCard(paymentMethodId: card.id);
    if (deleted) {
      setState(() => _savedCards.removeWhere((c) => c.id == card.id));
      if (mounted) showAppToast(context, 'Card removed');
    } else {
      if (mounted) showAppToast(context, 'Failed to remove card. Try again.');
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final file = await ImageUploadService.pickImage();
    if (file == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await ImageUploadService.uploadProfileImage(
        userId: _user?.uid ?? '',
        imageFile: file,
      );
      if (url != null) {
        _photoUrl = url;
        await _firestore
            .collection('users')
            .doc(_user?.uid)
            .update({'photoUrl': url});
        if (mounted) showAppToast(context, 'Photo updated');
      } else {
        if (mounted) {
          showAppToast(
            context,
            'Photo upload failed. ${ImageUploadService.failureUserHint()}',
          );
        }
      }
    } catch (e) {
      debugPrint('[CustomerProfile] photo upload failed: $e');
      if (mounted) {
        showAppToast(
          context,
          'Photo upload failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    final uErr = validateCustomerUsernameFormat(_nameController.text);
    if (uErr != null) {
      if (mounted) showAppToast(context, uErr);
      return;
    }
    final lookupRes = await LoginLookupSync.syncCustomerDisplayName(
      firestore: _firestore,
      uid: _user?.uid ?? '',
      email: _emailController.text.trim(),
      previousName: _loginLookupDisplayName,
      newName: _nameController.text.trim(),
    );
    if (lookupRes == LoginLookupSyncResult.nameAlreadyClaimed) {
      if (mounted) {
        showAppToast(context, 'This username is already taken. Choose another.');
      }
      return;
    }
    if (lookupRes == LoginLookupSyncResult.failed) {
      if (mounted) {
        showAppToast(
          context,
          'Could not update username. Check your connection and try again.',
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_lat != null && _lng != null) {
        data['lat'] = _lat;
        data['lng'] = _lng;
        data['address'] = _address;
      }
      final cityTrim = _cityController.text.trim();
      if (cityTrim.isNotEmpty) {
        data['city'] = cityTrim;
      } else {
        data['city'] = FieldValue.delete();
      }
      if (_photoUrl != null) data['photoUrl'] = _photoUrl;
      await _firestore.collection('users').doc(_user?.uid).update(data);
      _loginLookupDisplayName = _nameController.text.trim();

      if (!mounted) return;
      showAppToast(context, 'Profile updated successfully');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Something went wrong. Please try again later.');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _openLocationPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick Your Location'),
        content: SizedBox(
          width: 400,
          height: 450,
          child: LocationPicker(
            initialLat: _lat,
            initialLng: _lng,
            onLocationSelected: (lat, lng, address, inferredCity) {
              setState(() {
                _lat = lat;
                _lng = lng;
                _address = address;
                if (inferredCity != null && inferredCity.trim().isNotEmpty) {
                  _cityController.text = inferredCity.trim();
                }
              });
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await cartService.clearSessionForSignOut();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Skeletonizer(
      enabled: _loading,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(theme),
            const SizedBox(height: 18),
            const Text('Account').semiBold(),
            const SizedBox(height: 8),
            _buildMenuCard(
              theme,
              children: [
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.archive,
                  title: 'Order History',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => Scaffold(
                          backgroundColor:
                              Theme.of(ctx).colorScheme.background,
                          child: SafeArea(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Positioned.fill(
                                  child: CustomerOrdersView(
                                      showBackButton: true),
                                ),
                                const CustomerVoiceFabPositioned(
                                    hasBottomDock: false),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                _buildDivider(theme),
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.pinTop,
                  title: 'My Addresses',
                  onTap: _openLocationPicker,
                ),
                _buildDivider(theme),
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.cardStack,
                  title: 'Payments & Cards',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _CustomerPaymentsPage(
                          title: 'Payments & Cards',
                          child: _buildSavedCardsSection(theme),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('General').semiBold(),
            const SizedBox(height: 8),
            _buildMenuCard(
              theme,
              children: [
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.bell,
                  title: 'Notifications',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsView.customer(),
                      ),
                    );
                  },
                ),
                _buildDivider(theme),
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.gear,
                  title: 'Settings',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsView(),
                      ),
                    );
                  },
                ),
                _buildDivider(theme),
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.questionMarkCircled,
                  title: 'Help & Support',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HelpSupportView(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('User Account Settings').semiBold(),
            const SizedBox(height: 8),
            _buildMenuCard(
              theme,
              children: [
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.person,
                  title: 'Edit Profile',
                  onTap: _openEditProfileSheet,
                ),
                _buildDivider(theme),
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.exit,
                  title: 'Log Out',
                  destructive: true,
                  onTap: _logout,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme) {
    final displayName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Guest User';
    final displayEmail = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim()
        : (_user?.email ?? '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
            child: Stack(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _uploadingPhoto
                      ? Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        )
                      : _photoUrl != null && _photoUrl!.isNotEmpty
                          ? Image.network(
                              _photoUrl!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                RadixIcons.person,
                                size: 34,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : Icon(
                              RadixIcons.person,
                              size: 34,
                              color: theme.colorScheme.primary,
                            ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      RadixIcons.pencil2,
                      size: 14,
                      color: theme.colorScheme.primaryForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName).h4().semiBold(),
                const SizedBox(height: 4),
                Text(
                  displayEmail.isNotEmpty ? displayEmail : 'No email',
                  style: TextStyle(
                    color: theme.colorScheme.mutedForeground,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          GhostButton(
            density: ButtonDensity.compact,
            onPressed: _openEditProfileSheet,
            child: const Icon(RadixIcons.pencil2, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(ThemeData theme, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      thickness: 1,
      color: theme.colorScheme.border.withValues(alpha: 0.2),
    );
  }

  Widget _buildMenuRow(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? theme.colorScheme.destructive : theme.colorScheme.foreground;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (destructive
                        ? theme.colorScheme.destructive
                        : theme.colorScheme.primary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 16,
                  color: destructive
                      ? theme.colorScheme.destructive
                      : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              RadixIcons.chevronRight,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }

  void _openEditProfileSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.border.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Edit Profile').h4().semiBold(),
                  const SizedBox(height: 14),
                  _buildGeneralSettingsSection(theme),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: _saving
                        ? Center(
                            child: SizedBox.square(
                              dimension: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          )
                        : PrimaryButton(
                            onPressed: () async {
                              await _saveProfile();
                              if (mounted) Navigator.pop(ctx);
                            },
                            child: const Text('Save Changes'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGeneralSettingsSection(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RadixIcons.gear,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('General Settings').semiBold(),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          _labeledField(
            'Name',
            _nameController,
            'Lowercase letters, numbers, symbols only',
          ),
          _labeledField('Email', _emailController, 'Email address'),
          _labeledField('Phone', _phoneController, 'Phone number'),
          _labeledField(
            'City',
            _cityController,
            'e.g. Lahore — used to show nearby restaurants',
          ),
          const SizedBox(height: 8),
          const Text('Delivery Location').semiBold().small(),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_address.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(RadixIcons.pinTop,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ).small(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlineButton(
                    onPressed: _openLocationPicker,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(RadixIcons.crosshair1,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(_address.isEmpty
                            ? 'Set Location'
                            : 'Change Location'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedCardsSection(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RadixIcons.cardStack,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Payment Methods').semiBold(),
              const Spacer(),
              GhostButton(
                density: ButtonDensity.compact,
                onPressed: _loadSavedCards,
                child: const Icon(RadixIcons.reload, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingCards)
            Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else if (_savedCards.isEmpty)
            Text('No saved cards yet').muted().small()
          else
            ..._savedCards.map((card) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(RadixIcons.idCard,
                          size: 16, color: theme.colorScheme.foreground),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${card.brand.toUpperCase()} ···· ${card.last4}  (${card.expMonth}/${card.expYear})',
                        ).small(),
                      ),
                      GhostButton(
                        density: ButtonDensity.icon,
                        onPressed: () => _deleteCard(card),
                        child: Icon(RadixIcons.trash, size: 14,
                            color: theme.colorScheme.destructive),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlineButton(
              onPressed: _addCard,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(RadixIcons.plus,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Add Card'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField(
    String label,
    TextEditingController controller,
    String placeholder,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label).semiBold().small(),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            placeholder: Text(placeholder),
          ),
        ],
      ),
    );
  }

}

class _CustomerPaymentsPage extends StatelessWidget {
  final String title;
  final Widget child;

  const _CustomerPaymentsPage({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      child: SafeArea(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GhostButton(
                        density: ButtonDensity.compact,
                        onPressed: () => Navigator.pop(context),
                        child: const Icon(RadixIcons.arrowLeft, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(title).h4().semiBold(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: theme.colorScheme.foreground),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const CustomerVoiceFabPositioned(hasBottomDock: false),
          ],
        ),
      ),
    );
  }
}

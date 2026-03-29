import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' as material
    show AppBar,
        Icon,
        IconButton,
        Icons,
        InkWell,
        MaterialPageRoute,
        PopScope,
        Scaffold,
        ScrollViewKeyboardDismissBehavior,
        showDialog;
import 'package:skeletonizer/skeletonizer.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/services/image_upload_service.dart';
import 'package:speak_dine/services/login_lookup_sync.dart';
import 'package:speak_dine/services/payment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speak_dine/view/authScreens/login_view.dart';
import 'package:speak_dine/view/common/notifications_view.dart';
import 'package:speak_dine/view/common/settings_view.dart';
import 'package:speak_dine/view/common/merchant_support_view.dart';
import 'package:speak_dine/widgets/sd_lib_restaurant_category_picker.dart';
import 'package:speak_dine/widgets/location_picker.dart';

const _hourOptions = [
  '12:00 AM', '01:00 AM', '02:00 AM', '03:00 AM', '04:00 AM', '05:00 AM',
  '06:00 AM', '07:00 AM', '08:00 AM', '09:00 AM', '10:00 AM', '11:00 AM',
  '12:00 PM', '01:00 PM', '02:00 PM', '03:00 PM', '04:00 PM', '05:00 PM',
  '06:00 PM', '07:00 PM', '08:00 PM', '09:00 PM', '10:00 PM', '11:00 PM',
];

class RestaurantProfileView extends StatefulWidget {
  const RestaurantProfileView({super.key});

  @override
  State<RestaurantProfileView> createState() =>
      _RestaurantProfileViewState();
}

class _RestaurantPaymentsPage extends StatelessWidget {
  final String title;
  final Widget child;

  const _RestaurantPaymentsPage({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      child: SafeArea(
        child: Padding(
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
      ),
    );
  }
}

class _RestaurantProfileViewState extends State<RestaurantProfileView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Never cache at State init — [FirebaseAuth.instance.currentUser] can be null
  /// for a frame; always read fresh when saving or loading.
  String? get _restaurantUid => FirebaseAuth.instance.currentUser?.uid;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _loading = true;
  bool _uploadingRestaurantPhoto = false;
  bool _connectLoading = false;
  bool _profileDocExists = true;
  /// One photo for logo + discovery card ([profileImageUrl] / [coverImageUrl] kept in sync in Firestore).
  String? _restaurantImageUrl;
  String? _openTime;
  String? _closeTime;
  String? _stripeConnectId;
  String? _loginLookupRestaurantName;
  String? _restaurantCategoryId;
  bool _stripeConnectOnboarded = false;
  double? _lat;
  double? _lng;

  /// Pushed edit route listens to this; parent [setState] does not rebuild it.
  final ValueNotifier<bool> _savingNotifier = ValueNotifier<bool>(false);

  /// Serializes [Firestore] reads so a slow first fetch is not thrown away when a
  /// second call fails—see [_loadProfile] / [_loadProfileRun].
  Future<void> _profileLoadQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadProfile(forceServer: true);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _descriptionController.dispose();
    _savingNotifier.dispose();
    super.dispose();
  }

  static String? _nonEmptyUrl(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  static String _fieldString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// Enqueues a load so overlapping calls run one after another (no “stale”
  /// discard of a successful older response when a newer read fails).
  Future<void> _loadProfile({
    bool forceServer = false,
    bool showLoadingSkeleton = true,
  }) {
    _profileLoadQueue = _profileLoadQueue
        .catchError((Object _, StackTrace __) {})
        .then((_) => _loadProfileRun(
              forceServer: forceServer,
              showLoadingSkeleton: showLoadingSkeleton,
            ));
    return _profileLoadQueue;
  }

  Future<void> _loadProfileRun({
    required bool forceServer,
    required bool showLoadingSkeleton,
  }) async {
    final uid = _restaurantUid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (showLoadingSkeleton && mounted) setState(() => _loading = true);
    try {
      final doc = forceServer
          ? await _firestore
              .collection('restaurants')
              .doc(uid)
              .get(const GetOptions(source: Source.server))
          : await _firestore.collection('restaurants').doc(uid).get();
      if (!mounted) return;
      if (doc.exists) {
        final raw = doc.data();
        if (raw == null) {
          _profileDocExists = false;
          _emailController.text =
              (FirebaseAuth.instance.currentUser?.email ?? '').trim();
          _restaurantCategoryId ??= 'other';
        } else {
          _profileDocExists = true;
          final data = Map<String, dynamic>.from(raw as Map);
          _nameController.text = _fieldString(data, [
            'restaurantName',
            'name',
            'businessName',
            'signInRestaurantName',
          ]);
          _emailController.text = _fieldString(data, ['email']);
          if (_emailController.text.isEmpty) {
            _emailController.text =
                (FirebaseAuth.instance.currentUser?.email ?? '').trim();
          }
          _phoneController.text = _fieldString(data, [
            'phone',
            'phoneNumber',
            'mobile',
            'telephone',
            'contactPhone',
          ]);
          _addressController.text = _fieldString(data, ['address', 'street']);
          _cityController.text = _fieldString(data, ['city']);
          _lat = (data['lat'] as num?)?.toDouble();
          _lng = (data['lng'] as num?)?.toDouble();
          _descriptionController.text =
              _fieldString(data, ['description', 'about', 'bio']);
          final fromCover = _nonEmptyUrl(data['coverImageUrl']) ??
              _nonEmptyUrl(data['bannerUrl']) ??
              _nonEmptyUrl(data['coverUrl']) ??
              _nonEmptyUrl(data['bannerImageUrl']);
          final fromProfile = _nonEmptyUrl(data['profileImageUrl']) ??
              _nonEmptyUrl(data['logoUrl']) ??
              _nonEmptyUrl(data['photoUrl']) ??
              _nonEmptyUrl(data['imageUrl']);
          _restaurantImageUrl = fromProfile ?? fromCover;
          _openTime = data['openTime'] as String?;
          _closeTime = data['closeTime'] as String?;
          _stripeConnectId = data['stripeConnectId'] as String?;
          _stripeConnectOnboarded = data['stripeConnectOnboarded'] == true;
          final cat = data['restaurantCategory'] as String?;
          _restaurantCategoryId =
              (cat != null && cat.trim().isNotEmpty) ? cat.trim() : 'other';
          final signIn = _fieldString(data, ['signInRestaurantName']);
          _loginLookupRestaurantName = signIn.isNotEmpty
              ? signIn
              : _nameController.text.trim();
        }
      } else {
        _profileDocExists = false;
        _emailController.text =
            (FirebaseAuth.instance.currentUser?.email ?? '').trim();
        _restaurantCategoryId ??= 'other';
      }
      _restaurantCategoryId ??= 'other';
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (_stripeConnectId != null && !_stripeConnectOnboarded) {
      _refreshConnectStatus();
    }
  }

  Future<void> _refreshConnectStatus() async {
    if (_stripeConnectId == null) return;
    final ready = await PaymentService.checkConnectStatus(
      accountId: _stripeConnectId!,
      restaurantId: _restaurantUid ?? '',
    );
    if (mounted) setState(() => _stripeConnectOnboarded = ready);
  }

  Future<void> _startConnectOnboarding() async {
    setState(() => _connectLoading = true);

    if (_stripeConnectId != null) {
      final url = await PaymentService.getOnboardingLink(
        accountId: _stripeConnectId!,
      );
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, webOnlyWindowName: '_self');
        }
      } else {
        if (mounted) showAppToast(context, 'Could not load onboarding. Try again.');
      }
    } else {
      final result = await PaymentService.createConnectAccount(
        restaurantId: _restaurantUid ?? '',
        email: _emailController.text.trim(),
        businessName: _nameController.text.trim(),
      );
      if (result != null) {
        _stripeConnectId = result['accountId'];
        final url = result['onboardingUrl']!;
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, webOnlyWindowName: '_self');
        }
      } else {
        if (mounted) showAppToast(context, 'Failed to set up payments. Try again.');
      }
    }

    if (mounted) setState(() => _connectLoading = false);
  }

  /// Same flow as customer profile [CustomerProfileView._pickAndUploadPhoto]:
  /// pick → upload via [ImageUploadService.uploadProfileImage] (restaurant cover folder) → Firestore.
  Future<void> _pickRestaurantPhoto() async {
    final file = await ImageUploadService.pickImage();
    if (file == null) return;
    final uid = _restaurantUid;
    if (uid == null) {
      if (mounted) showAppToast(context, 'Not signed in.');
      return;
    }

    setState(() => _uploadingRestaurantPhoto = true);
    try {
      final url = await ImageUploadService.uploadProfileImage(
        userId: uid,
        imageFile: file,
        kind: ProfileImageKind.restaurantCover,
      );
      if (url != null) {
        _restaurantImageUrl = url;
        try {
          final ref = _firestore.collection('restaurants').doc(uid);
          final patch = {
            'profileImageUrl': url,
            'coverImageUrl': url,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (_profileDocExists) {
            await ref.update(patch);
          } else {
            await ref.set({
              ...patch,
              'uid': uid,
              'role': 'restaurant',
            }, SetOptions(merge: true));
            if (mounted) setState(() => _profileDocExists = true);
          }
          if (mounted) showAppToast(context, 'Photo updated');
        } catch (e) {
          debugPrint('[RestaurantProfile] photo Firestore sync: $e');
          if (mounted) {
            showAppToast(
              context,
              'Photo uploaded but could not sync. Tap Save in Edit Profile.',
            );
          }
        }
      } else {
        if (mounted) {
          showAppToast(
            context,
            'Photo upload failed. ${ImageUploadService.failureUserHint()}',
          );
        }
      }
    } catch (e) {
      debugPrint('[RestaurantProfile] photo upload failed: $e');
      if (mounted) {
        showAppToast(
          context,
          'Photo upload failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingRestaurantPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    final uid = _restaurantUid;
    if (uid == null) {
      if (mounted) {
        showAppToast(context, 'Not signed in.');
      }
      return;
    }

    final trimmedName = _nameController.text.trim();
    final lookupRes = await LoginLookupSync.syncRestaurantName(
      firestore: _firestore,
      uid: uid,
      email: _emailController.text.trim(),
      previousName: _loginLookupRestaurantName,
      newName: trimmedName,
    );
    if (lookupRes == LoginLookupSyncResult.nameAlreadyClaimed) {
      if (mounted) {
        showAppToast(
          context,
          'This restaurant name is already used for sign-in. Choose another.',
        );
      }
      return;
    }
    if (lookupRes == LoginLookupSyncResult.failed) {
      debugPrint(
        '[RestaurantProfile] loginLookup sync failed; saving venue doc anyway '
        '(same as main branch: Firestore profile is source of truth).',
      );
    }

    _savingNotifier.value = true;
    try {
      final data = <String, dynamic>{
        'restaurantName': trimmedName,
        // Legacy/key used by some screens; keeps dashboard & search aligned.
        'name': trimmedName,
        'signInRestaurantName': trimmedName,
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'description': _descriptionController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_restaurantImageUrl != null) {
        data['profileImageUrl'] = _restaurantImageUrl;
        data['coverImageUrl'] = _restaurantImageUrl;
      }
      if (_openTime != null) data['openTime'] = _openTime;
      if (_closeTime != null) data['closeTime'] = _closeTime;
      if (_restaurantCategoryId != null && _restaurantCategoryId!.isNotEmpty) {
        data['restaurantCategory'] = _restaurantCategoryId;
      }
      if (_lat != null && _lng != null) {
        data['lat'] = _lat;
        data['lng'] = _lng;
      }

      final ref = _firestore.collection('restaurants').doc(uid);
      if (_profileDocExists) {
        await ref.update(data);
      } else {
        await ref.set({
          ...data,
          'uid': uid,
          'role': 'restaurant',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) setState(() => _profileDocExists = true);
      }
      _loginLookupRestaurantName = _nameController.text.trim();

      if (!mounted) return;
      showAppToast(context, 'Profile updated successfully');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Something went wrong. Please try again later.');
    }
    if (mounted) {
      _savingNotifier.value = false;
    }
  }

  void _openRestaurantLocationPicker([VoidCallback? afterPicked]) {
    final maxW = MediaQuery.sizeOf(context).width - 48;
    material.showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurant location'),
        content: SizedBox(
          width: maxW.clamp(280.0, 420.0),
          height: 480,
          child: LocationPicker(
            initialLat: _lat,
            initialLng: _lng,
            onLocationSelected: (lat, lng, address, inferredCity) {
              setState(() {
                _lat = lat;
                _lng = lng;
                if (address.trim().isNotEmpty) {
                  _addressController.text = address;
                }
                if (inferredCity != null && inferredCity.trim().isNotEmpty) {
                  _cityController.text = inferredCity.trim();
                }
              });
              afterPicked?.call();
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  String _avatarInitials() {
    final n = _nameController.text.trim();
    if (n.isEmpty) return '·';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length >= 2 &&
        parts[0].isNotEmpty &&
        parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    if (n.length >= 2) return n.substring(0, 2).toUpperCase();
    return n[0].toUpperCase();
  }

  Widget _buildProfileHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: (_loading || _uploadingRestaurantPhoto)
                ? null
                : _pickRestaurantPhoto,
            child: Container(
              width: 112,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  width: 2,
                ),
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
              ),
              clipBehavior: Clip.antiAlias,
              child: _uploadingRestaurantPhoto
                  ? Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : _restaurantImageUrl != null &&
                          _restaurantImageUrl!.isNotEmpty
                      ? Image.network(
                          _restaurantImageUrl!,
                          width: 112,
                          height: 72,
                          fit: BoxFit.cover,
                          key: ValueKey<String>(_restaurantImageUrl!),
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              _avatarInitials(),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            _avatarInitials(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameController.text.isNotEmpty
                      ? _nameController.text
                      : 'Your venue',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).semiBold(),
                const SizedBox(height: 4),
                Text(
                  'Tap the photo to add or change your restaurant image',
                  maxLines: 2,
                ).muted().small(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      material.MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      keyboardDismissBehavior:
          material.ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_profileDocExists) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.destructive.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.destructive.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                'Your venue record is missing. You can still edit below; '
                'tap Save in Edit Profile after connecting with support if needed.',
                style: TextStyle(
                  color: theme.colorScheme.destructive,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildProfileHeader(context, theme),
          const SizedBox(height: 18),
          Skeletonizer(
            enabled: _loading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Account').semiBold(),
            const SizedBox(height: 8),
            _buildMenuCard(
              theme,
              children: [
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.person,
                  title: 'Edit Profile',
                  onTap: _loading ? null : () => _openEditRestaurantSheet(),
                ),
                _buildDivider(theme),
                _buildMenuRow(
                  theme,
                  icon: RadixIcons.cardStack,
                  title: 'Payment Setup',
                  onTap: () {
                    Navigator.of(context).push(
                      material.MaterialPageRoute(
                        builder: (_) => _RestaurantPaymentsPage(
                          title: 'Payment Setup',
                          child: _buildStripeConnectSection(theme),
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
                      material.MaterialPageRoute(
                        builder: (_) => const NotificationsView.restaurant(),
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
                      material.MaterialPageRoute(
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
                      material.MaterialPageRoute(
                        builder: (_) => const MerchantSupportView(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlineButton(
                onPressed: _logout,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      RadixIcons.exit,
                      size: 16,
                      color: theme.colorScheme.destructive,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        color: theme.colorScheme.destructive,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
    VoidCallback? onTap,
    bool destructive = false,
  }) {
    final disabled = onTap == null;
    final color = destructive
        ? theme.colorScheme.destructive
        : disabled
            ? theme.colorScheme.mutedForeground
            : theme.colorScheme.foreground;
    return material.InkWell(
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

  Future<void> _openEditRestaurantSheet() async {
    if (!mounted) return;
    // Do not re-fetch here: a second [Source.server] read can race the first load
    // and (previously) discard good data if the newer read failed; also preserves
    // any unsaved edits already in the text controllers.
    setState(() {});

    final theme = Theme.of(context);
    await Navigator.of(context).push<void>(
      material.MaterialPageRoute<void>(
        builder: (pageCtx) => material.PopScope<void>(
          canPop: true,
          child: material.Scaffold(
            backgroundColor: theme.colorScheme.background,
            appBar: material.AppBar(
              backgroundColor: theme.colorScheme.background,
              surfaceTintColor: Colors.transparent,
              foregroundColor: theme.colorScheme.foreground,
              elevation: 0,
              leading: material.IconButton(
                icon: material.Icon(material.Icons.arrow_back),
                color: theme.colorScheme.foreground,
                tooltip: 'Back',
                onPressed: () {
                  Navigator.of(pageCtx).maybePop();
                },
              ),
              title: Text(
                'Edit Profile',
                style: TextStyle(
                  color: theme.colorScheme.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          material.ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: StatefulBuilder(
                        builder: (ctx, setSheetState) {
                          void bumpSheet() {
                            setSheetState(() {});
                            setState(() {});
                          }

                          return _buildRestaurantGeneralSettingsSection(
                            ctx,
                            theme,
                            onSheetChanged: bumpSheet,
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      16 + MediaQuery.paddingOf(pageCtx).bottom,
                    ),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _savingNotifier,
                      builder: (ctx, saving, _) {
                        return saving
                            ? Center(
                                child: SizedBox.square(
                                  dimension: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              )
                            : SizedBox(
                                width: double.infinity,
                                child: PrimaryButton(
                                  onPressed: () async {
                                    await _saveProfile();
                                    if (pageCtx.mounted) {
                                      Navigator.of(pageCtx).maybePop();
                                    }
                                  },
                                  child: const Text('Save Changes'),
                                ),
                              );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRestaurantGeneralSettingsSection(
    BuildContext context,
    ThemeData theme, {
    required VoidCallback onSheetChanged,
  }) {
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
          _buildRestaurantPhotoSection(context, theme),
          const SizedBox(height: 24),
          _labeledField(
            'Restaurant Name',
            _nameController,
            'Restaurant name',
            onChanged: (_) => onSheetChanged(),
          ),
          if (_nameController.text.trim().startsWith('venue_')) ...[
            const SizedBox(height: 4),
            const Text(
              'This is a temporary sign-in name. Update it to your public restaurant name.',
            ).muted().small(),
            const SizedBox(height: 8),
          ],
          _labeledField('Email', _emailController, 'Email address'),
          _labeledField('Phone', _phoneController, 'Phone number'),
          _labeledField('Address', _addressController, 'Address'),
          _labeledField(
            'City',
            _cityController,
            'City for discovery (must match customer city)',
          ),
          const SizedBox(height: 8),
          const Text('Pin on map').semiBold().small(),
          const SizedBox(height: 6),
          Text(
            'Sets address and city from the map so customers can find you.',
          ).muted().small(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlineButton(
              onPressed: () =>
                  _openRestaurantLocationPicker(onSheetChanged),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(RadixIcons.crosshair1,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    _lat != null && _lng != null
                        ? 'Update map location'
                        : 'Set location on map',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SdLibRestaurantCategoryPicker(
            theme: theme,
            dense: true,
            selectedId: _restaurantCategoryId,
            onChanged: (id) {
              _restaurantCategoryId = id;
              onSheetChanged();
            },
          ),
          const SizedBox(height: 16),
          _labeledField(
              'Description', _descriptionController, 'About your place'),
          const Text('Business Hours').semiBold().small(),
          const SizedBox(height: 6),
          _buildBusinessHours(theme, onSheetChanged: onSheetChanged),
        ],
      ),
    );
  }

  Widget _buildRestaurantPhotoSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Restaurant photo').semiBold().small(),
        const Text('Shown on your profile and in discovery — optional')
            .muted()
            .small(),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _uploadingRestaurantPhoto ? null : _pickRestaurantPhoto,
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _uploadingRestaurantPhoto
                ? Center(
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                : _restaurantImageUrl != null &&
                        _restaurantImageUrl!.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            _restaurantImageUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 160,
                            key: ValueKey<String>(_restaurantImageUrl!),
                            errorBuilder: (_, __, ___) =>
                                _restaurantPhotoPlaceholder(theme),
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.background
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(RadixIcons.camera,
                                      size: 14,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Change',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : _restaurantPhotoPlaceholder(theme),
          ),
        ),
      ],
    );
  }

  Widget _restaurantPhotoPlaceholder(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(RadixIcons.image, size: 32, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          'Tap to choose one photo',
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessHours(
    ThemeData theme, {
    required VoidCallback onSheetChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Open').muted().small(),
              const SizedBox(height: 4),
              Select<String>(
                value: _openTime,
                onChanged: (value) {
                  _openTime = value;
                  setState(() {});
                  onSheetChanged();
                },
                itemBuilder: (context, item) => Text(item),
                placeholder: const Text('Open time'),
                popupConstraints: const BoxConstraints(maxHeight: 250),
                popup: (_) => SelectPopup(
                  items: SelectItemList(
                    children: [
                      for (final h in _hourOptions)
                        SelectItemButton(value: h, child: Text(h)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Close').muted().small(),
              const SizedBox(height: 4),
              Select<String>(
                value: _closeTime,
                onChanged: (value) {
                  _closeTime = value;
                  setState(() {});
                  onSheetChanged();
                },
                itemBuilder: (context, item) => Text(item),
                placeholder: const Text('Close time'),
                popupConstraints: const BoxConstraints(maxHeight: 250),
                popup: (_) => SelectPopup(
                  items: SelectItemList(
                    children: [
                      for (final h in _hourOptions)
                        SelectItemButton(value: h, child: Text(h)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStripeConnectSection(ThemeData theme) {
    final bool isOnboarded = _stripeConnectOnboarded;

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
              Icon(
                RadixIcons.cardStack,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('Payments & Stripe').semiBold(),
              const Spacer(),
              if (isOnboarded)
                Icon(RadixIcons.checkCircled,
                    size: 16, color: Colors.green.shade700)
              else if (_stripeConnectId != null)
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: _refreshConnectStatus,
                  child: const Icon(RadixIcons.reload, size: 14),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isOnboarded) ...[
            Text(
              'Payments are enabled. You will receive payouts directly to your bank.',
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlineButton(
                onPressed: () async {
                  if (_stripeConnectId == null) return;
                  final url = await PaymentService.getConnectDashboardLink(
                    accountId: _stripeConnectId!,
                  );
                  if (url != null) {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, webOnlyWindowName: '_self');
                    }
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(RadixIcons.externalLink,
                        size: 14, color: theme.colorScheme.foreground),
                    const SizedBox(width: 8),
                    const Text('Stripe Dashboard'),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(
              _stripeConnectId != null
                  ? 'Onboarding started but not completed. Finish setup to accept payments.'
                  : 'No payout details added yet. Set up Stripe to receive online payments from customers.',
            ).muted().small(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _connectLoading
                  ? Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : PrimaryButton(
                      onPressed: _startConnectOnboarding,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(RadixIcons.globe, size: 14),
                          const SizedBox(width: 8),
                          Text(_stripeConnectId != null
                              ? 'Continue Setup'
                              : 'Set Up Payments'),
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _labeledField(
    String label,
    TextEditingController controller,
    String placeholder, {
    ValueChanged<String>? onChanged,
  }) {
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
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

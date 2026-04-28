import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/services/image_upload_service.dart';
import 'package:speak_dine/services/payment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:speak_dine/view/authScreens/login_view.dart';

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

class _RestaurantProfileViewState extends State<RestaurantProfileView>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingCover = false;
  bool _connectLoading = false;
  String? _coverImageUrl;
  String? _openTime;
  String? _closeTime;
  String? _stripeConnectId;
  bool _stripeConnectOnboarded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _stripeConnectId != null &&
        !_stripeConnectOnboarded) {
      _refreshConnectStatus();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final doc =
          await _firestore.collection('restaurants').doc(user?.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _nameController.text = data['restaurantName'] ?? '';
        _emailController.text = data['email'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _addressController.text = data['address'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _coverImageUrl = data['coverImageUrl'] as String?;
        _openTime = data['openTime'] as String?;
        _closeTime = data['closeTime'] as String?;
        _stripeConnectId = data['stripeConnectId'] as String?;
        _stripeConnectOnboarded = data['stripeConnectOnboarded'] == true;
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    if (mounted) setState(() => _loading = false);
    if (_stripeConnectId != null && !_stripeConnectOnboarded) {
      _refreshConnectStatus();
    }
  }

  Future<void> _refreshConnectStatus() async {
    if (_stripeConnectId == null) return;
    final ready = await PaymentService.checkConnectStatus(
      accountId: _stripeConnectId!,
      restaurantId: user?.uid ?? '',
    );
    if (mounted) setState(() => _stripeConnectOnboarded = ready);
  }

  Future<void> _startConnectOnboarding() async {
    setState(() => _connectLoading = true);

    try {
      if (_stripeConnectId != null) {
        final url = await PaymentService.getOnboardingLink(
          accountId: _stripeConnectId!,
        );
        if (url != null) {
          final uri = Uri.parse(url);
          await launchUrl(uri,
              mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
        } else {
          if (mounted) showAppToast(context, 'Could not load onboarding. Try again.', isError: true);
        }
      } else {
        final result = await PaymentService.createConnectAccount(
          restaurantId: user?.uid ?? '',
          email: _emailController.text.trim(),
          businessName: _nameController.text.trim(),
        );
        if (result != null) {
          _stripeConnectId = result['accountId'];
          final url = result['onboardingUrl']!;
          final uri = Uri.parse(url);
          await launchUrl(uri,
              mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
        } else {
          if (mounted) showAppToast(context, 'Failed to set up payments. Try again.', isError: true);
        }
      }
    } catch (e) {
      debugPrint('[ConnectOnboarding] Error: $e');
      if (mounted) showAppToast(context, 'Could not open payment setup. Try again.', isError: true);
    }

    if (mounted) setState(() => _connectLoading = false);
  }

  Future<void> _pickCoverImage() async {
    final file = await ImageUploadService.pickImage();
    if (file == null) return;

    setState(() => _uploadingCover = true);
    final url = await ImageUploadService.uploadProfileImage(
      userId: user?.uid ?? '',
      imageFile: file,
    );
    if (url != null) {
      _coverImageUrl = url;
      await _firestore
          .collection('restaurants')
          .doc(user?.uid)
          .update({'coverImageUrl': url});
      if (mounted) showAppToast(context, 'Cover image updated');
    } else {
      if (mounted) showAppToast(context, 'Upload failed. Please try again.', isError: true);
    }
    if (mounted) setState(() => _uploadingCover = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'restaurantName': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'description': _descriptionController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_coverImageUrl != null) data['coverImageUrl'] = _coverImageUrl;
      if (_openTime != null) data['openTime'] = _openTime;
      if (_closeTime != null) data['closeTime'] = _closeTime;

      await _firestore.collection('restaurants').doc(user?.uid).update(data);

      if (!mounted) return;
      showAppToast(context, 'Profile updated successfully');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Something went wrong. Please try again later.', isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _logout() async {
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Profile').h4().semiBold(),
            const Text('Update your restaurant information')
                .muted()
                .small(),
            const SizedBox(height: 24),
            _buildCoverImagePicker(theme),
            const SizedBox(height: 24),
            _labeledField(
                'Restaurant Name', _nameController, 'Restaurant name'),
            _labeledField('Email', _emailController, 'Email address'),
            _labeledField('Phone', _phoneController, 'Phone number'),
            _labeledField('Address', _addressController, 'Address'),
            _labeledField('Description', _descriptionController,
                'About your place'),
            const Text('Business Hours').semiBold().small(),
            const SizedBox(height: 6),
            _buildBusinessHours(theme),
            const SizedBox(height: 24),
            _buildStripeConnectSection(theme),
            const SizedBox(height: 24),
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
                      onPressed: _saveProfile,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Text('Save Changes')],
                      ),
                    ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlineButton(
                onPressed: _logout,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(RadixIcons.exit, size: 16,
                        color: theme.colorScheme.destructive),
                    const SizedBox(width: 8),
                    Text(
                      'Log Out',
                      style: TextStyle(
                          color: theme.colorScheme.destructive),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImagePicker(ThemeData theme) {
    return GestureDetector(
      onTap: _uploadingCover ? null : _pickCoverImage,
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
        child: _uploadingCover
            ? Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            : _coverImageUrl != null && _coverImageUrl!.isNotEmpty
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _coverPlaceholder(theme),
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
                                  size: 14, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Text('Change',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : _coverPlaceholder(theme),
      ),
    );
  }

  Widget _coverPlaceholder(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(RadixIcons.image, size: 32, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        const Text('Tap to add a cover photo').muted().small(),
      ],
    );
  }

  Widget _buildBusinessHours(ThemeData theme) {
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
                onChanged: (value) => setState(() => _openTime = value),
                itemBuilder: (context, item) => Text(item),
                placeholder: const Text('Open time'),
                popupConstraints: const BoxConstraints(maxHeight: 200),
                popup: SelectPopup(
                  items: SelectItemList(
                    children: _hourOptions
                        .map((h) => SelectItemButton(value: h, child: Text(h)))
                        .toList(),
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
                onChanged: (value) => setState(() => _closeTime = value),
                itemBuilder: (context, item) => Text(item),
                placeholder: const Text('Close time'),
                popupConstraints: const BoxConstraints(maxHeight: 200),
                popup: SelectPopup(
                  items: SelectItemList(
                    children: _hourOptions
                        .map((h) => SelectItemButton(value: h, child: Text(h)))
                        .toList(),
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
          color: isOnboarded
              ? Colors.green.withAlpha(60)
              : theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOnboarded ? RadixIcons.check : RadixIcons.globe,
                size: 16,
                color: isOnboarded ? Colors.green : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('Payment Setup').semiBold(),
              const Spacer(),
              if (_stripeConnectId != null && !isOnboarded)
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: _refreshConnectStatus,
                  child: const Icon(RadixIcons.reload, size: 14),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
                      await launchUrl(uri,
              webOnlyWindowName: kIsWeb ? '_self' : null,
              mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
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
                  : 'Set up Stripe to receive online payments from customers.',
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

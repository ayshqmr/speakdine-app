import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:speak_dine/utils/toast_helper.dart';
import 'package:speak_dine/utils/pkr_format.dart';
import 'package:speak_dine/services/image_upload_service.dart';
import 'package:speak_dine/widgets/menu_item_network_image.dart';
import 'package:speak_dine/constants/menu_dish_category.dart';
import 'package:flutter/material.dart'
    show
        AlwaysScrollableScrollPhysics,
        FloatingActionButton,
        RefreshIndicator,
        ScrollViewKeyboardDismissBehavior;
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Each dish has a [dishCategory] (appetizer, main, dessert, drink). Venue type
/// stays on the restaurant doc (`restaurantCategory`, Profile / signup).

String? _menuPriceValidationMessage(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'Enter a price greater than zero.';
  }
  final p = double.tryParse(trimmed);
  if (p == null || p <= 0) {
    return 'Enter a valid price greater than zero.';
  }
  return null;
}

/// Newest [createdAt] first; items without [createdAt] (legacy) sort last.
void _sortMenuDocsNewestFirst(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  int compare(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ca = a.data()['createdAt'];
    final cb = b.data()['createdAt'];
    final aTs = ca is Timestamp ? ca : null;
    final bTs = cb is Timestamp ? cb : null;
    if (aTs == null && bTs == null) return a.id.compareTo(b.id);
    if (aTs == null) return 1;
    if (bTs == null) return -1;
    final c = bTs.compareTo(aTs);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  docs.sort(compare);
}

class MenuManagementView extends StatefulWidget {
  const MenuManagementView({
    super.key,
    this.openAddDialogAfterBuild = false,
    this.onConsumedOpenAdd,
  });

  /// When this flips to true, the add-dish dialog opens once (dashboard "+" flow).
  final bool openAddDialogAfterBuild;
  final VoidCallback? onConsumedOpenAdd;

  @override
  State<MenuManagementView> createState() => _MenuManagementViewState();
}

class _MenuManagementViewState extends State<MenuManagementView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _menuStream;

  @override
  void initState() {
    super.initState();
    _bindMenuStream();
  }

  void _bindMenuStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _menuStream = uid == null
        ? null
        : _firestore
            .collection('restaurants')
            .doc(uid)
            .collection('menu')
            .snapshots();
  }

  Future<void> _refreshMenuFromServer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _firestore
        .collection('restaurants')
        .doc(uid)
        .collection('menu')
        .get(const GetOptions(source: Source.server));
    if (!mounted) return;
    setState(_bindMenuStream);
  }

  Widget _dishCategorySelector(
    ThemeData theme,
    String selectedId,
    void Function(String id) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Category').semiBold().small(),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in MenuDishCategory.idsInMenuOrder)
              GestureDetector(
                onTap: () => onChanged(id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selectedId == id
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selectedId == id
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primary.withValues(alpha: 0.25),
                      width: selectedId == id ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    MenuDishCategory.labelFor(id),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          selectedId == id ? FontWeight.w700 : FontWeight.w500,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(MenuManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openAddDialogAfterBuild &&
        !oldWidget.openAddDialogAfterBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final theme = Theme.of(context);
        try {
          _showAddItemDialog(theme);
        } finally {
          widget.onConsumedOpenAdd?.call();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('restaurants').doc(user?.uid).snapshots(),
      builder: (context, restaurantSnap) {
        final map = restaurantSnap.data?.data() as Map<String, dynamic>?;
        final stripeOnboarded = map?['stripeConnectOnboarded'] == true;
        final showPaymentHint =
            restaurantSnap.hasData && !stripeOnboarded;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showPaymentHint) _buildCardPaymentsHint(theme),
            Expanded(child: _buildMenuContent(theme)),
          ],
        );
      },
    );
  }

  Widget _buildCardPaymentsHint(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(RadixIcons.infoCircled,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Card payments from customers need Stripe payment setup in Profile. '
                'You can still add and edit dishes anytime.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.foreground.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuContent(ThemeData theme) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Menu').h4().semiBold(),
                  const Text(
                    'Add dishes with name, description, and price — your venue type is set once in Profile.',
                  ).muted().small(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _menuStream == null
                  ? const Center(child: Text('Sign in to manage your menu.'))
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _menuStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return _buildMenuSkeleton();
                        }
                        if (snapshot.hasError) {
                          debugPrint('[MenuManagement] Menu stream error: ${snapshot.error}');
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (context.mounted) {
                              showAppToast(context, 'Unable to load menu. Please try again.');
                            }
                          });
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(RadixIcons.crossCircled,
                                    size: 48,
                                    color: theme.colorScheme.destructive),
                                const SizedBox(height: 16),
                                const Text('Unable to load menu').semiBold(),
                              ],
                            ),
                          );
                        }
                        if (!snapshot.hasData ||
                            snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(RadixIcons.reader,
                                    size: 48,
                                    color:
                                        theme.colorScheme.mutedForeground),
                                const SizedBox(height: 16),
                                const Text('No menu items yet').semiBold(),
                                const SizedBox(height: 8),
                                const Text('Tap the + button to add your first dish')
                                    .muted()
                                    .small(),
                              ],
                            ),
                          );
                        }
                        final docs =
                            List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                          snapshot.data!.docs,
                        );
                        final grouped = {
                          for (final id in MenuDishCategory.idsInMenuOrder)
                            id: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                        };
                        for (final doc in docs) {
                          final data = doc.data();
                          final cat = MenuDishCategory.normalizeId(
                              data['dishCategory'],
                          );
                          grouped[cat]!.add(doc);
                        }
                        for (final list in grouped.values) {
                          _sortMenuDocsNewestFirst(list);
                        }
                        var isFirstSection = true;
                        final tiles = <Widget>[];
                        for (final catId in MenuDishCategory.idsInMenuOrder) {
                          final section = grouped[catId]!;
                          if (section.isEmpty) continue;
                          tiles.add(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: isFirstSection ? 0 : 22,
                                    bottom: 10,
                                  ),
                                  child: Text(
                                    MenuDishCategory.sectionHeadingFor(catId),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                ...section.asMap().entries.map((e) {
                                  final doc = e.value;
                                  final item = doc.data();
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: e.key < section.length - 1 ? 12 : 0,
                                    ),
                                    child: _buildMenuItem(
                                      context,
                                      theme,
                                      item,
                                      doc.id,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                          isFirstSection = false;
                        }
                        return RefreshIndicator(
                          onRefresh: _refreshMenuFromServer,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: tiles,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.small(
            onPressed: () => _showAddItemDialog(theme),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.primaryForeground,
            child: const Icon(RadixIcons.plus, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuSkeleton() {
    return Skeletonizer(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: List.generate(
          5,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Bone.text(words: 2),
                        const SizedBox(height: 8),
                        const Bone.text(words: 4, fontSize: 12),
                        const SizedBox(height: 8),
                        const Bone.text(words: 1),
                      ],
                    ),
                  ),
                  const Bone.icon(),
                  const SizedBox(width: 8),
                  const Bone.icon(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    ThemeData theme,
    Map<String, dynamic> item,
    String itemId,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          menuItemImageOrPlaceholder(
            context: context,
            item: item,
            size: 48,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? 'Item').semiBold(),
                if (item['description'] != null &&
                    item['description'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item['description'].toString().trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ).muted().small(),
                ],
                const SizedBox(height: 8),
                Text(
                  formatPkr(item['price']),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          GhostButton(
            density: ButtonDensity.icon,
            onPressed: () => _showEditItemDialog(theme, item, itemId),
            child: const Icon(RadixIcons.pencil1, size: 16),
          ),
          GhostButton(
            density: ButtonDensity.icon,
            onPressed: () => _deleteItem(itemId),
            child: Icon(RadixIcons.trash,
                size: 16, color: theme.colorScheme.destructive),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog(ThemeData theme) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController();
    XFile? pickedImage;
    bool uploading = false;
    var dishCategory = MenuDishCategory.main;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Menu Item'),
          content: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Image').semiBold().small(),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final file = await ImageUploadService.pickImage();
                      if (file != null) {
                        setDialogState(() => pickedImage = file);
                      }
                    },
                    child: Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.2),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: pickedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: FutureBuilder<List<int>>(
                                future: pickedImage!.readAsBytes(),
                                builder: (context, snap) {
                                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                                  return Image.memory(
                                    Uint8List.fromList(snap.data!),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  );
                                },
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(RadixIcons.image, size: 28, color: theme.colorScheme.primary),
                                const SizedBox(height: 6),
                                const Text('Tap to add image (optional)').muted().small(),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dishCategorySelector(theme, dishCategory, (id) {
                    setDialogState(() => dishCategory = id);
                  }),
                  const SizedBox(height: 12),
                  const Text('Name').semiBold().small(),
                  const SizedBox(height: 6),
                  TextField(
                      controller: nameController,
                      placeholder: const Text('Item name')),
                  const SizedBox(height: 12),
                  const Text('Description').semiBold().small(),
                  const SizedBox(height: 6),
                  TextField(
                      controller: descController,
                      placeholder: const Text('Description')),
                  const SizedBox(height: 12),
                  const Text('Price (Rs.)').semiBold().small(),
                  const SizedBox(height: 6),
                  TextField(
                      controller: priceController,
                      placeholder: const Text('e.g. 450')),
                ],
              ),
            ),
          ),
          actions: [
            OutlineButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            uploading
                ? SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : PrimaryButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        showAppToast(context, 'Item name is required');
                        return;
                      }
                      final priceErr =
                          _menuPriceValidationMessage(priceController.text);
                      if (priceErr != null) {
                        showAppToast(context, priceErr);
                        return;
                      }
                      final price =
                          double.parse(priceController.text.trim());

                      setDialogState(() => uploading = true);
                      var imageUploadFailed = false;
                      String? imageUrl;
                      try {
                        if (pickedImage != null) {
                          imageUrl = await ImageUploadService.uploadMenuImage(
                            restaurantId: user?.uid ?? '',
                            imageFile: pickedImage!,
                          );
                          if (imageUrl == null) imageUploadFailed = true;
                        }
                        final ok = await _addItem(
                          name,
                          descController.text,
                          price,
                          dishCategory: dishCategory,
                          imageUrl: imageUrl,
                        );
                        if (!mounted) return;
                        if (imageUploadFailed) {
                          showAppToast(
                            context,
                            'Could not upload image. Item was added without a photo. '
                            '${ImageUploadService.failureUserHint()}',
                          );
                        }
                        if (!ok || !ctx.mounted) return;
                        Navigator.pop(ctx);
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => uploading = false);
                        }
                      }
                    },
                    child: const Text('Add'),
                  ),
          ],
        ),
      ),
    );
  }

  void _showEditItemDialog(
      ThemeData theme, Map<String, dynamic> item, String itemId) {
    final nameController = TextEditingController(text: item['name']);
    final descController =
        TextEditingController(text: item['description']);
    final priceController =
        TextEditingController(text: item['price']?.toString());
    String? existingImageUrl = item['imageUrl'] as String?;
    XFile? pickedImage;
    bool uploading = false;
    var dishCategory = MenuDishCategory.normalizeId(item['dishCategory']);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Menu Item'),
          content: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Image').semiBold().small(),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final file = await ImageUploadService.pickImage();
                      if (file != null) {
                        setDialogState(() {
                          pickedImage = file;
                          existingImageUrl = null;
                        });
                      }
                    },
                    child: Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: pickedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: FutureBuilder<List<int>>(
                                future: pickedImage!.readAsBytes(),
                                builder: (context, snap) {
                                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                                  return Image.memory(
                                    Uint8List.fromList(snap.data!),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  );
                                },
                              ),
                            )
                          : existingImageUrl != null && existingImageUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: MenuItemNetworkImage(
                                    url: existingImageUrl!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 120,
                                    placeholder: _imagePickerPlaceholder(theme),
                                  ),
                                )
                              : _imagePickerPlaceholder(theme),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dishCategorySelector(theme, dishCategory, (id) {
                    setDialogState(() => dishCategory = id);
                  }),
                  const SizedBox(height: 12),
                  const Text('Name').semiBold().small(),
                  const SizedBox(height: 6),
                  TextField(
                      controller: nameController,
                      placeholder: const Text('Item name')),
                  const SizedBox(height: 12),
                  const Text('Description').semiBold().small(),
                  const SizedBox(height: 6),
                  TextField(
                      controller: descController,
                      placeholder: const Text('Description')),
                  const SizedBox(height: 12),
                  const Text('Price (Rs.)').semiBold().small(),
                  const SizedBox(height: 6),
                  TextField(
                      controller: priceController,
                      placeholder: const Text('e.g. 450')),
                ],
              ),
            ),
          ),
          actions: [
            OutlineButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            uploading
                ? SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : PrimaryButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        showAppToast(context, 'Item name is required');
                        return;
                      }
                      final priceErr =
                          _menuPriceValidationMessage(priceController.text);
                      if (priceErr != null) {
                        showAppToast(context, priceErr);
                        return;
                      }
                      final price =
                          double.parse(priceController.text.trim());

                      setDialogState(() => uploading = true);
                      var newImageUploadFailed = false;
                      String? imageUrl = existingImageUrl;
                      try {
                        if (pickedImage != null) {
                          final uploaded =
                              await ImageUploadService.uploadMenuImage(
                            restaurantId: user?.uid ?? '',
                            imageFile: pickedImage!,
                          );
                          if (uploaded != null) {
                            imageUrl = uploaded;
                          } else {
                            newImageUploadFailed = true;
                            imageUrl = null;
                          }
                        }
                        final ok = await _updateItem(
                          itemId,
                          name,
                          descController.text,
                          price,
                          dishCategory: dishCategory,
                          imageUrl: imageUrl,
                        );
                        if (!mounted) return;
                        if (newImageUploadFailed && pickedImage != null) {
                          showAppToast(
                            context,
                            'Could not upload new image. Your previous photo was kept. '
                            '${ImageUploadService.failureUserHint()}',
                          );
                        }
                        if (!ok || !ctx.mounted) return;
                        Navigator.pop(ctx);
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => uploading = false);
                        }
                      }
                    },
                    child: const Text('Save'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _imagePickerPlaceholder(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(RadixIcons.image, size: 28, color: theme.colorScheme.primary),
        const SizedBox(height: 6),
        const Text('Tap to change image').muted().small(),
      ],
    );
  }

  Future<bool> _addItem(
    String name,
    String description,
    double price, {
    required String dishCategory,
    String? imageUrl,
  }) async {
    if (name.isEmpty) {
      showAppToast(context, 'Item name is required');
      return false;
    }
    if (price <= 0) {
      showAppToast(context, 'Enter a valid price greater than zero.');
      return false;
    }
    try {
      final data = <String, dynamic>{
        'name': name,
        'description': description,
        'price': price,
        'dishCategory': MenuDishCategory.normalizeId(dishCategory),
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (imageUrl != null) data['imageUrl'] = imageUrl;
      await _firestore
          .collection('restaurants')
          .doc(user?.uid)
          .collection('menu')
          .add(data);
      if (!mounted) return true;
      showAppToast(context, '$name added to menu');
      return true;
    } catch (e) {
      if (!mounted) return false;
      showAppToast(context, 'Something went wrong. Please try again later.');
      return false;
    }
  }

  Future<bool> _updateItem(
    String itemId,
    String name,
    String description,
    double price, {
    required String dishCategory,
    String? imageUrl,
  }) async {
    if (name.isEmpty) {
      showAppToast(context, 'Item name is required');
      return false;
    }
    if (price <= 0) {
      showAppToast(context, 'Enter a valid price greater than zero.');
      return false;
    }
    try {
      final data = <String, dynamic>{
        'name': name,
        'description': description,
        'price': price,
        'dishCategory': MenuDishCategory.normalizeId(dishCategory),
      };
      if (imageUrl != null) data['imageUrl'] = imageUrl;
      await _firestore
          .collection('restaurants')
          .doc(user?.uid)
          .collection('menu')
          .doc(itemId)
          .update(data);
      if (!mounted) return true;
      showAppToast(context, '$name updated');
      return true;
    } catch (e) {
      if (!mounted) return false;
      showAppToast(context, 'Something went wrong. Please try again later.');
      return false;
    }
  }

  Future<void> _deleteItem(String itemId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final uid = user?.uid;
        if (uid == null) {
          if (mounted) showAppToast(context, 'Not signed in.');
          return;
        }
        await _firestore
            .collection('restaurants')
            .doc(uid)
            .collection('menu')
            .doc(itemId)
            .delete();
        await _firestore
            .collection('restaurants')
            .doc(uid)
            .collection('menu')
            .get(const GetOptions(source: Source.server));
        if (!mounted) return;
        showAppToast(context, 'Item deleted');
      } catch (e) {
        if (!mounted) return;
        showAppToast(context, 'Something went wrong. Please try again later.');
      }
    }
  }
}

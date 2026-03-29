import 'dart:async';
import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:speak_dine/config/api_keys.dart';

/// Customer avatar, restaurant photos, and menu dish images (same owner [userId]).
enum ProfileImageKind { customerAvatar, restaurantCover, menuItem }

class ImageUploadService {
  static final _picker = ImagePicker();
  static const Duration _uploadTimeout = Duration(seconds: 10);

  /// Short hint for toast when [uploadMenuImage] / profile uploads return null.
  static String failureUserHint() {
    if (imgbbApiKey.trim().isNotEmpty) {
      return 'Check your ImgBB key or network.';
    }
    return 'Enable Firebase Storage and deploy storage.rules from the project.';
  }

  static Future<XFile?> pickImage() async {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 75,
    );
  }

  static Future<String?> uploadMenuImage({
    required String restaurantId,
    required XFile imageFile,
  }) {
    return uploadProfileImage(
      userId: restaurantId,
      imageFile: imageFile,
      kind: ProfileImageKind.menuItem,
    );
  }

  static Future<String?> uploadProfileImage({
    required String userId,
    required XFile imageFile,
    ProfileImageKind kind = ProfileImageKind.customerAvatar,
  }) {
    final t = DateTime.now().millisecondsSinceEpoch;
    final String storageFolder;
    final String logicalName;
    switch (kind) {
      case ProfileImageKind.customerAvatar:
        storageFolder = 'customer_avatar';
        logicalName = 'profile_${userId}_$t';
      case ProfileImageKind.restaurantCover:
        storageFolder = 'restaurant_cover';
        logicalName = 'profile_${userId}_$t';
      case ProfileImageKind.menuItem:
        storageFolder = 'menu';
        logicalName = 'menu_${userId}_$t';
    }
    return _uploadImage(
      ownerUid: userId,
      imageFile: imageFile,
      logicalName: logicalName,
      storageFolder: storageFolder,
    );
  }

  /// Same storage rules as [uploadProfileImage] with [ProfileImageKind.restaurantCover].
  static Future<String?> uploadRestaurantLogo({
    required String restaurantId,
    required XFile imageFile,
  }) {
    return uploadProfileImage(
      userId: restaurantId,
      imageFile: imageFile,
      kind: ProfileImageKind.restaurantCover,
    );
  }

  /// Uses ImgBB when [imgbbApiKey] is set; otherwise Firebase Storage (no extra API key).
  static Future<String?> _uploadImage({
    required String ownerUid,
    required XFile imageFile,
    required String logicalName,
    required String storageFolder,
  }) async {
    try {
      if (imgbbApiKey.trim().isNotEmpty) {
        return await _uploadToImgbb(
          imageFile: imageFile,
          imageName: logicalName,
        ).timeout(_uploadTimeout);
      }
      return await _uploadToFirebaseStorage(
        ownerUid: ownerUid,
        imageFile: imageFile,
        storageFolder: storageFolder,
      ).timeout(_uploadTimeout);
    } on TimeoutException {
      debugPrint('[ImageUpload] Timed out after ${_uploadTimeout.inSeconds}s');
      return null;
    }
  }

  static String _extensionFor(XFile file) {
    final n = file.name.toLowerCase();
    final dot = n.lastIndexOf('.');
    if (dot >= 0 && dot < n.length - 1) {
      final ext = n.substring(dot + 1);
      if (ext.length <= 8 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return 'jpg';
  }

  static String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  static Future<String?> _uploadToFirebaseStorage({
    required String ownerUid,
    required XFile imageFile,
    required String storageFolder,
  }) async {
    try {
      final ext = _extensionFor(imageFile);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name.hashCode.abs()}.$ext';
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_uploads')
          .child(ownerUid)
          .child(storageFolder)
          .child(fileName);

      final bytes = await imageFile.readAsBytes();
      final mime = imageFile.mimeType;
      final contentType = (mime != null && mime.startsWith('image/'))
          ? mime
          : _contentTypeForExtension(ext);

      await ref.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      return await ref.getDownloadURL();
    } on FirebaseException catch (e) {
      debugPrint(
        '[ImageUpload] Firebase Storage failed: ${e.code} — ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('[ImageUpload] Firebase Storage failed: $e');
      return null;
    }
  }

  static Future<String?> _uploadToImgbb({
    required XFile imageFile,
    required String imageName,
  }) async {
    if (imgbbApiKey.isEmpty) {
      debugPrint('[ImageUpload] IMGBB_API_KEY not set. '
          'Run with --dart-define=IMGBB_API_KEY=your_key');
      return null;
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload'),
        body: {
          'key': imgbbApiKey,
          'image': base64Image,
          'name': imageName,
        },
      ).timeout(_uploadTimeout);

      if (response.statusCode != 200) {
        debugPrint('[ImageUpload] ImgBB returned status ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final success = json['success'] as bool? ?? false;

      if (!success) {
        debugPrint('[ImageUpload] ImgBB upload failed: ${response.body}');
        return null;
      }

      final imageData = json['data'] as Map<String, dynamic>;
      return imageData['url'] as String?;
    } catch (e) {
      debugPrint('[ImageUpload] Upload failed: $e');
      return null;
    }
  }
}

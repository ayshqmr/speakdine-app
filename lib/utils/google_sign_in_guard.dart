import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:speak_dine/config/api_keys.dart';

/// Android (google_sign_in 7.x) needs the OAuth **Web** client ID at init.
/// iOS uses URL schemes in Info.plist; this guard is Android-only.
bool get isGoogleSignInMissingAndroidWebClientId {
  if (kIsWeb) return false;
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  return googleWebClientId.trim().isEmpty;
}

const String googleSignInMissingWebClientIdMessage =
    'Google Sign-In on Android needs your Web Client ID. In Firebase: '
    'Authentication → Sign-in method → Google, copy the “Web client” ID, '
    'then set googleWebClientId in lib/config/api_keys.dart (see api_keys.example.dart). '
    'Also add your app’s SHA-1 in Project settings and re-download google-services.json if needed.';

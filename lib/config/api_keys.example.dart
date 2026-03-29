/// Template for [api_keys.dart]. Copy to `api_keys.dart` in this folder and fill in,
/// or use `--dart-define` (see `api_keys.dart` comments).
///
/// The real `api_keys.dart` is gitignored.

const String stripeServerUrl = String.fromEnvironment(
  'STRIPE_SERVER_URL',
  defaultValue: '',
);

const String imgbbApiKey = String.fromEnvironment(
  'IMGBB_API_KEY',
  defaultValue: '',
);

/// OAuth 2.0 **Web** client ID (`….apps.googleusercontent.com`).
/// Required for Google Sign-In on Android with `google_sign_in` 7.x.
/// Firebase Console → Authentication → Google → Web client ID, or use
/// `--dart-define=GOOGLE_WEB_CLIENT_ID=your-id.apps.googleusercontent.com`
const String googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '',
);

/// Same value as server env LOGIN_RESOLVE_SECRET (header X-Login-Resolve-Secret).
const String loginResolveSecret = String.fromEnvironment(
  'LOGIN_RESOLVE_SECRET',
  defaultValue: '',
);

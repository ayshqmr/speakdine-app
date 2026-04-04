import 'dart:html' as html;

/// Remove `session_id` / `stripe_checkout` from the address bar after handling return.
void clearStripeCheckoutQueryFromBrowserUrl() {
  try {
    final loc = html.window.location;
    final path = loc.pathname ?? '/';
    html.window.history.replaceState(null, '', path);
  } catch (_) {}
}

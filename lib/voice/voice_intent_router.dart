import 'package:speak_dine/services/text_to_speech_service.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/voice/voice_intent_models.dart';

/// Executes light navigation + TTS feedback from a [VoiceIntentResult].
///
/// Returns the phrase spoken so the UI can show a “live script” line.
class VoiceIntentRouter {
  VoiceIntentRouter({
    required this.switchToTab,
    required TextToSpeechService tts,
  }) : _tts = tts;

  /// Customer shell tab index: 0 home, 1 cart, 2 orders, 3 payments, 4 profile.
  final void Function(int index) switchToTab;
  final TextToSpeechService _tts;

  static const int tabHome = 0;
  static const int tabCart = 1;
  static const int tabOrders = 2;
  static const int tabPayments = 3;
  static const int tabProfile = 4;

  Future<String> handle(VoiceIntentResult r) async {
    await _tts.stop();

    switch (r.kind) {
      case VoiceIntentKind.nonFood:
        const spoken =
            'That does not sound like a food or ordering request. '
            'Try asking about restaurants, dishes, your cart, or your profile.';
        await _tts.speak(spoken);
        return spoken;

      case VoiceIntentKind.userProfile:
        switchToTab(tabProfile);
        const spoken = 'Opening your profile.';
        await _tts.speak(spoken);
        return spoken;

      case VoiceIntentKind.orderPlacement:
        final item = r.itemName?.trim();
        if (item != null && item.isNotEmpty) {
          switchToTab(tabHome);
          CustomerVoiceBridge.instance.applySearchQuery?.call(item);
          final spoken =
              'Searching for $item. Open a restaurant, then add items to your cart.';
          await _tts.speak(spoken);
          return spoken;
        } else {
          switchToTab(tabCart);
          const spoken = 'Opening your cart.';
          await _tts.speak(spoken);
          return spoken;
        }

      case VoiceIntentKind.categoryBrowse:
        switchToTab(tabHome);
        CustomerVoiceBridge.instance.applyCategoryId?.call(r.categoryId);
        final label = r.extractedQuery ?? 'that category';
        final spoken = 'Showing $label restaurants.';
        await _tts.speak(spoken);
        return spoken;

      case VoiceIntentKind.restaurantInfo:
        switchToTab(tabHome);
        final name = r.restaurantName?.trim();
        if (name != null && name.isNotEmpty) {
          final opener = CustomerVoiceBridge.instance.openRestaurantByName;
          if (opener != null) {
            final opened = await opener(name);
            if (!opened) {
              const spoken = 'Restaurant not found. Try another name.';
              await _tts.speak(spoken);
              return spoken;
            }
            final spoken = 'Opening $name.';
            await _tts.speak(spoken);
            return spoken;
          } else {
            CustomerVoiceBridge.instance.applySearchQuery?.call(name);
            final spoken = 'Searching for $name.';
            await _tts.speak(spoken);
            return spoken;
          }
        } else {
          final q = r.extractedQuery ?? '';
          if (q.isNotEmpty) {
            CustomerVoiceBridge.instance.applySearchQuery?.call(q);
          }
          const spoken =
              'Here are restaurants matching your search. Tap one for hours and address.';
          await _tts.speak(spoken);
          return spoken;
        }

      case VoiceIntentKind.dishDescription:
        switchToTab(tabHome);
        final q = r.extractedQuery ?? r.itemName ?? '';
        if (q.isNotEmpty) {
          CustomerVoiceBridge.instance.applySearchQuery?.call(q);
        }
        const spoken =
            'Showing search results. Open a restaurant to see dish details.';
        await _tts.speak(spoken);
        return spoken;

      case VoiceIntentKind.unknown:
        switchToTab(tabHome);
        final q = r.extractedQuery ?? '';
        if (q.isNotEmpty) {
          CustomerVoiceBridge.instance.applySearchQuery?.call(q);
        }
        if (r.isFoodOrOrderingRelated) {
          const spoken =
              'Searching the app for that. Refine by saying cart, profile, or a restaurant name.';
          await _tts.speak(spoken);
          return spoken;
        } else {
          const spoken = 'Sorry, I did not understand. Please try again.';
          await _tts.speak(spoken);
          return spoken;
        }
    }
  }
}

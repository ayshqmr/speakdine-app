import 'package:flutter/foundation.dart';

/// Hooks registered by [UserHomeView] so voice commands can update explore UI
/// without tight coupling to widget state.
class CustomerVoiceBridge {
  CustomerVoiceBridge._();
  static final CustomerVoiceBridge instance = CustomerVoiceBridge._();

  void Function(String query)? applySearchQuery;
  void Function(String? categoryId)? applyCategoryId;
  /// Returns true if a detail screen was opened.
  Future<bool> Function(String name)? openRestaurantByName;

  /// Latest speech-to-text while holding the mic (and final line after release).
  final ValueNotifier<String> userSpeechLine = ValueNotifier<String>('');

  /// Last phrase the assistant spoke via TTS after a hold session.
  final ValueNotifier<String> assistantSpeechLine = ValueNotifier<String>('');

  /// True while the customer is holding the voice FAB (listening).
  final ValueNotifier<bool> voiceListening = ValueNotifier<bool>(false);

  void clear() {
    applySearchQuery = null;
    applyCategoryId = null;
    openRestaurantByName = null;
  }

  void clearSpeechLines() {
    userSpeechLine.value = '';
    assistantSpeechLine.value = '';
  }
}

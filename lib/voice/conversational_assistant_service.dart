import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:speak_dine/config/api_keys.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/voice/speaktime_assistant_system_prompt.dart';
import 'package:speak_dine/voice/voice_intent_models.dart';

/// Gemini turn: spoken script for TTS + optional structured intent for the app.
class ConversationalAssistantTurn {
  const ConversationalAssistantTurn({required this.speech, this.intent});

  final String speech;
  final VoiceIntentResult? intent;
}

/// Full SpeakTime system prompt + situational context → JSON { speech, intent }.
class ConversationalAssistantService {
  const ConversationalAssistantService();

  static const Duration _timeout = Duration(seconds: 18);

  Future<ConversationalAssistantTurn?> process({
    required String userUtterance,
    required String situationalContext,
  }) async {
    final text = userUtterance.trim();
    if (text.isEmpty || geminiApiKey.trim().isEmpty) {
      return null;
    }

    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$geminiModel:generateContent',
    );

    final userBlock =
        '''
CONTEXT (facts for this turn; do not read labels like "CONTEXT" aloud):
$situationalContext

USER SAID:
$text
''';

    try {
      final response = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': geminiApiKey,
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': kSpeaktimeAssistantSystemPrompt},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': userBlock},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.35,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[SpeakTimeAssistant] HTTP ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = root['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        return null;
      }
      final first = candidates.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }
      final content = first['content'];
      if (content is! Map<String, dynamic>) {
        return null;
      }
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) {
        return null;
      }
      final part = parts.first;
      if (part is! Map<String, dynamic>) {
        return null;
      }
      final rawJson = (part['text'] ?? '').toString().trim();
      if (rawJson.isEmpty) {
        return null;
      }

      final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
      final speech = (parsed['speech'] ?? '').toString().trim();
      if (speech.isEmpty) {
        return null;
      }

      final intentMap = parsed['intent'];
      VoiceIntentResult? intent;
      if (intentMap is Map<String, dynamic>) {
        intent = _intentFromAssistantJson(intentMap);
      }

      return ConversationalAssistantTurn(speech: speech, intent: intent);
    } on TimeoutException {
      debugPrint('[SpeakTimeAssistant] Timed out after ${_timeout.inSeconds}s');
      return null;
    } catch (e) {
      debugPrint('[SpeakTimeAssistant] failed: $e');
      return null;
    }
  }

  VoiceIntentResult? _intentFromAssistantJson(Map<String, dynamic> m) {
    if (!m.containsKey('kind')) {
      return null;
    }
    final ks = (m['kind'] ?? '').toString().trim();
    if (ks.isEmpty) {
      return null;
    }
    final kind = _kindFromString(ks);

    String? clean(dynamic v) {
      if (v == null) {
        return null;
      }
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    var categoryId = clean(m['categoryId']);
    if (kind != VoiceIntentKind.selectMenuItem) {
      categoryId = null;
    }
    if (categoryId != null &&
        !kSdLibRestaurantCategories.any((c) => c.id == categoryId)) {
      categoryId = null;
    }

    return VoiceIntentResult(
      kind: kind,
      isFoodOrOrderingRelated: true,
      confidence: 0.75,
      extractedQuery: clean(m['extractedQuery']),
      restaurantName: clean(m['restaurantName']),
      itemName: clean(m['itemName']),
      categoryId: categoryId,
      settingKey: clean(m['settingKey']),
      settingValue: clean(m['settingValue']),
    );
  }

  VoiceIntentKind _kindFromString(String v) {
    switch (v) {
      case 'nonFood':
        return VoiceIntentKind.nonFood;
      case 'unknown':
        return VoiceIntentKind.unknown;
      case 'cancelAction':
        return VoiceIntentKind.cancelAction;
      case 'addToCartRequest':
        return VoiceIntentKind.addToCartRequest;
      case 'selectMenuItem':
        return VoiceIntentKind.selectMenuItem;
      case 'confirmAddToCart':
        return VoiceIntentKind.confirmAddToCart;
      case 'openCartIntent':
        return VoiceIntentKind.openCartIntent;
      case 'cartNaturalLanguageEdit':
        return VoiceIntentKind.cartNaturalLanguageEdit;
      case 'initiateCheckout':
        return VoiceIntentKind.initiateCheckout;
      case 'confirmOrderUIOnly':
        return VoiceIntentKind.confirmOrderUIOnly;
      case 'cancelCheckout':
        return VoiceIntentKind.cancelCheckout;
      case 'openSettings':
        return VoiceIntentKind.openSettings;
      case 'toggleSetting':
        return VoiceIntentKind.toggleSetting;
      case 'updateSettingValue':
        return VoiceIntentKind.updateSettingValue;
      case 'addToCartIntent':
        return VoiceIntentKind.addToCartIntent;
      case 'ambiguousOrderIntent':
        return VoiceIntentKind.ambiguousOrderIntent;
      case 'goHome':
        return VoiceIntentKind.goHome;
      case 'goBack':
        return VoiceIntentKind.goBack;
      case 'whereAmI':
        return VoiceIntentKind.whereAmI;
      case 'trackOrderIntent':
        return VoiceIntentKind.trackOrderIntent;
      case 'suggestNextAction':
        return VoiceIntentKind.suggestNextAction;
      case 'clarifyUserIntent':
        return VoiceIntentKind.clarifyUserIntent;
      case 'cancelCurrentFlow':
        return VoiceIntentKind.cancelCurrentFlow;
      default:
        return VoiceIntentKind.unknown;
    }
  }
}

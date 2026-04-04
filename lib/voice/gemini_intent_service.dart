import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:speak_dine/config/api_keys.dart';
import 'package:speak_dine/constants/sd_lib_restaurant_categories.dart';
import 'package:speak_dine/voice/voice_intent_models.dart';

/// Cloud LLM intent parser (Gemini) with strict JSON output.
class GeminiIntentService {
  const GeminiIntentService();

  static const Duration _timeout = Duration(seconds: 12);

  static const String _allowedKinds = '''
nonFood, unknown, cancelAction,
addToCartRequest, selectMenuItem, confirmAddToCart,
openCartIntent, cartNaturalLanguageEdit,
initiateCheckout, confirmOrderUIOnly, cancelCheckout,
openSettings, toggleSetting, updateSettingValue,
addToCartIntent, ambiguousOrderIntent,
goHome, goBack, whereAmI, trackOrderIntent,
suggestNextAction, clarifyUserIntent, cancelCurrentFlow''';

  Future<VoiceIntentResult?> classify(String utterance) async {
    final text = utterance.trim();
    if (text.isEmpty || geminiApiKey.trim().isEmpty) {
      return null;
    }

    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$geminiModel:generateContent',
    );

    final categoryIds = kSdLibRestaurantCategories.map((e) => e.id).join(', ');
    final prompt =
        '''
Classify this SpeakDine CUSTOMER voice command into exactly ONE intent.

Allowed kind values (exact spelling):
$_allowedKinds

Optional categoryId only for selectMenuItem when user names a cuisine category: [$categoryIds]

Return STRICT JSON only:
{
  "kind": "<one allowed kind>",
  "isFoodOrOrderingRelated": true_or_false,
  "confidence": 0_to_1,
  "extractedQuery": "",
  "restaurantName": "",
  "itemName": "",
  "categoryId": "",
  "settingKey": "",
  "settingValue": ""
}

Rules:
- addToCartRequest: user wants to add food; put dish in itemName or extractedQuery.
- confirmAddToCart: yes / add it / confirm / put in cart while meaning confirm.
- initiateCheckout: user wants to place order; app opens cart payment options (COD vs online). confirmOrderUIOnly: only remind to confirm on screen.
- ambiguousOrderIntent: could mean order food vs place order vs cart.
- updateSettingValue: use settingKey username + settingValue for name changes.
- cancelAction / cancelCurrentFlow: stop or never mind.
- trackOrderIntent: user wants to track an active order, see delivery status, or where the order is.
- cartNaturalLanguageEdit: change cart by voice in one sentence (remove, add one more, etc.); put full utterance in extractedQuery.

Utterance:
"$text"
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
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.1,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[GeminiIntent] HTTP ${response.statusCode}: ${response.body}',
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
      return _toIntent(parsed);
    } on TimeoutException {
      debugPrint('[GeminiIntent] Timed out after ${_timeout.inSeconds}s');
      return null;
    } catch (e) {
      debugPrint('[GeminiIntent] parse/request failed: $e');
      return null;
    }
  }

  VoiceIntentResult _toIntent(Map<String, dynamic> m) {
    final kindRaw = (m['kind'] ?? '').toString().trim();
    final kind = _kindFromString(kindRaw);
    final confidenceNum = m['confidence'];
    final conf = confidenceNum is num ? confidenceNum.toDouble() : 0.5;

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
      isFoodOrOrderingRelated: (m['isFoodOrOrderingRelated'] == true),
      confidence: conf.clamp(0.0, 1.0),
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

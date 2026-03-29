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

  static const Duration _timeout = Duration(seconds: 10);

  Future<VoiceIntentResult?> classify(String utterance) async {
    final text = utterance.trim();
    if (text.isEmpty || geminiApiKey.trim().isEmpty) return null;

    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$geminiModel:generateContent',
    );

    final categoryIds = kSdLibRestaurantCategories.map((e) => e.id).join(', ');
    final prompt = '''
Classify this SpeakDine customer voice command into ONE intent.

Allowed intents:
- nonFood
- unknown
- restaurantInfo
- dishDescription
- categoryBrowse
- userProfile
- orderPlacement

Allowed categoryId values (only for categoryBrowse): [$categoryIds]

Return STRICT JSON only with this schema:
{
  "kind": "one_of_the_allowed_intents",
  "isFoodOrOrderingRelated": true_or_false,
  "confidence": 0_to_1_number,
  "extractedQuery": "optional_string_or_empty",
  "restaurantName": "optional_string_or_empty",
  "itemName": "optional_string_or_empty",
  "categoryId": "optional_category_id_or_empty"
}

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
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.1,
                'responseMimeType': 'application/json',
              }
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
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final part = parts.first;
      if (part is! Map<String, dynamic>) return null;
      final rawJson = (part['text'] ?? '').toString().trim();
      if (rawJson.isEmpty) return null;

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
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    var categoryId = clean(m['categoryId']);
    if (kind != VoiceIntentKind.categoryBrowse) {
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
    );
  }

  VoiceIntentKind _kindFromString(String v) {
    switch (v) {
      case 'nonFood':
        return VoiceIntentKind.nonFood;
      case 'restaurantInfo':
        return VoiceIntentKind.restaurantInfo;
      case 'dishDescription':
        return VoiceIntentKind.dishDescription;
      case 'categoryBrowse':
        return VoiceIntentKind.categoryBrowse;
      case 'userProfile':
        return VoiceIntentKind.userProfile;
      case 'orderPlacement':
        return VoiceIntentKind.orderPlacement;
      case 'unknown':
      default:
        return VoiceIntentKind.unknown;
    }
  }
}

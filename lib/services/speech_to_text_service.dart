import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Customer speech-to-text facade (permissions + listen lifecycle).
class SpeechToTextService {
  SpeechToTextService();

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _ready = false;

  bool get isListening => _stt.isListening;
  bool get isReady => _ready;

  Future<bool> init() async {
    _ready = await _stt.initialize(
      onError: (e) => debugPrint('[SpeechToText] $e'),
      onStatus: (s) => debugPrint('[SpeechToText] status=$s'),
    );
    return _ready;
  }

  /// [onResultText] receives (text, isFinal). Prefer acting on commands when [isFinal].
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResultText,
    String? localeId,
    Duration listenFor = const Duration(seconds: 12),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_ready) {
      final ok = await init();
      if (!ok) return false;
    }
    if (_stt.isListening) return true;

    await _stt.listen(
      localeId: localeId,
      listenFor: listenFor,
      pauseFor: pauseFor,
      onResult: (result) {
        onResultText(result.recognizedWords, result.finalResult);
      },
    );
    return true;
  }

  Future<void> stopListening() async => _stt.stop();

  Future<void> cancelListening() async => _stt.cancel();
}

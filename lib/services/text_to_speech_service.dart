import 'package:flutter_tts/flutter_tts.dart';

/// Customer text-to-speech facade.
class TextToSpeechService {
  TextToSpeechService() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _configured = true;
  }

  Future<void> speak(
    String text, {
    String? language,
    bool interrupt = true,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _ensureConfigured();
    if (interrupt) await _tts.stop();
    if (language != null) await _tts.setLanguage(language);
    await _tts.speak(t);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}

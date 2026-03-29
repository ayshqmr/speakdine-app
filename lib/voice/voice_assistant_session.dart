import 'package:speak_dine/services/speech_to_text_service.dart';
import 'package:speak_dine/services/text_to_speech_service.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/voice/voice_intent_classifier.dart';
import 'package:speak_dine/voice/voice_intent_router.dart';

/// Hold-to-talk: listen while the mic is held; on release run intent + TTS once.
class VoiceAssistantSession {
  VoiceAssistantSession({
    required void Function(int tabIndex) switchToTab,
    this.onMicNotReady,
    this.onCouldNotStartListening,
  }) : _switchToTab = switchToTab {
    _router = VoiceIntentRouter(switchToTab: _switchToTab, tts: _tts);
  }

  final void Function(int tabIndex) _switchToTab;
  final void Function()? onMicNotReady;
  final void Function()? onCouldNotStartListening;
  final SpeechToTextService _stt = SpeechToTextService();
  final TextToSpeechService _tts = TextToSpeechService();
  late final VoiceIntentRouter _router;
  final VoiceIntentClassifier _classifier = const VoiceIntentClassifier();

  bool _initialized = false;
  bool _holding = false;
  String _latestText = '';

  bool get isHolding => _holding;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = await _stt.init();
  }

  Future<void> onHoldStart() async {
    await ensureInitialized();
    final bridge = CustomerVoiceBridge.instance;
    if (!_initialized) {
      bridge.voiceListening.value = false;
      onMicNotReady?.call();
      return;
    }

    if (_holding) return;
    _holding = true;
    bridge.voiceListening.value = true;
    bridge.assistantSpeechLine.value = '';
    _latestText = '';
    bridge.userSpeechLine.value = '';

    await _stt.cancelListening();
    await _tts.stop();

    final started = await _stt.startListening(
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 10),
      onResultText: (text, _) {
        _latestText = text;
        bridge.userSpeechLine.value = text;
      },
    );
    if (!started) {
      _holding = false;
      bridge.voiceListening.value = false;
      onCouldNotStartListening?.call();
    }
  }

  Future<void> onHoldEnd() async {
    final bridge = CustomerVoiceBridge.instance;
    if (!_holding) return;
    _holding = false;
    bridge.voiceListening.value = false;

    await _stt.stopListening();

    final text = _latestText.trim();
    bridge.userSpeechLine.value = text;
    if (text.isEmpty) {
      return;
    }

    final intent = _classifier.classify(text);
    final spoken = await _router.handle(intent);
    bridge.assistantSpeechLine.value = spoken.trim();
  }

  void dispose() {
    _stt.cancelListening();
    _tts.stop();
    CustomerVoiceBridge.instance.voiceListening.value = false;
  }
}

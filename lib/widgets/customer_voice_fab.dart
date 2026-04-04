import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speak_dine/voice/customer_voice_bridge.dart';
import 'package:speak_dine/widgets/voice_assistant_sheet.dart';

/// Matches [CustomerShell]: FAB sits above [AppDock] when the dock is visible.
abstract final class CustomerVoiceFabLayout {
  static const double right = 8;
  static const double bottomWithDock = 88;
  static const double bottomFullScreen = 24;
}

/// Help (?) + hold-to-talk microphone. Combine with [CustomerVoiceFabPositioned] or an [Align].
class CustomerVoiceMicRow extends StatelessWidget {
  const CustomerVoiceMicRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bridge = CustomerVoiceBridge.instance;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GhostButton(
          density: ButtonDensity.icon,
          onPressed: () => showVoiceAssistantSheet(context),
          child: Icon(
            RadixIcons.questionMarkCircled,
            size: 22,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 4),
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => bridge.voiceMicHoldStart?.call(),
          onPointerUp: (_) => bridge.voiceMicHoldEnd?.call(),
          onPointerCancel: (_) => bridge.voiceMicHoldEnd?.call(),
          child: ValueListenableBuilder<bool>(
            valueListenable: bridge.voiceListening,
            builder: (context, listening, _) {
              return buildVoiceFab(
                theme,
                listening: listening,
                onPressed: () {},
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Bottom-right voice controls for use inside a [Stack] (with [clipBehavior: Clip.none] if needed).
class CustomerVoiceFabPositioned extends StatelessWidget {
  const CustomerVoiceFabPositioned({
    super.key,
    required this.hasBottomDock,
  });

  /// [true] when the main [CustomerShell] bottom dock is visible behind this overlay.
  final bool hasBottomDock;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: CustomerVoiceFabLayout.right,
      bottom: hasBottomDock
          ? CustomerVoiceFabLayout.bottomWithDock
          : CustomerVoiceFabLayout.bottomFullScreen,
      child: const CustomerVoiceMicRow(),
    );
  }
}

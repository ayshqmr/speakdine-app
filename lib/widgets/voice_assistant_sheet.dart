import 'package:flutter/material.dart' as material
    show Colors, FloatingActionButton, Icon, Icons, showModalBottomSheet;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Short help for the hold-to-talk voice flow (primary interaction is the mic FAB).
class VoiceAssistantHelpPanel extends StatelessWidget {
  const VoiceAssistantHelpPanel({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: theme.colorScheme.border.withValues(alpha: 0.2)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.border.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                material.Icon(material.Icons.mic,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('SpeakDine voice').h4().semiBold(),
                const Spacer(),
                GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: onClose,
                  child: const Icon(RadixIcons.cross2, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'SpeakDine is built for voice-first ordering. Press and hold the microphone, speak, then release. '
              'The assistant guides you step by step and reads replies aloud. '
              'Final order confirmation always happens on screen for safety.\n\n'
              'On the home screen you can read your last line and the assistant reply above the restaurant list.',
              style: TextStyle(
                color: theme.colorScheme.foreground,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              onPressed: onClose,
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the voice help sheet.
Future<void> showVoiceAssistantSheet(BuildContext context) {
  return material.showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: material.Colors.transparent,
    builder: (ctx) {
      return VoiceAssistantHelpPanel(
        onClose: () => Navigator.pop(ctx),
      );
    },
  );
}

/// Floating mic button: visual only; parent [Listener] handles press-and-hold.
Widget buildVoiceFab(
  ThemeData theme, {
  required bool listening,
  VoidCallback? onPressed,
}) {
  return material.FloatingActionButton(
    onPressed: onPressed,
    backgroundColor: listening
        ? theme.colorScheme.primary.withValues(alpha: 0.85)
        : theme.colorScheme.primary,
    child: material.Icon(
      listening ? material.Icons.mic : material.Icons.mic_none_outlined,
      color: theme.colorScheme.primaryForeground,
    ),
  );
}

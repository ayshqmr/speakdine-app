import 'package:flutter/widgets.dart';

/// Restores platform [MediaQuery.viewInsets] for descendants. Shadcn
/// [Scaffold] clears bottom insets on its body; without this, focused fields
/// low on the screen may not scroll above the keyboard.
class RestoreKeyboardViewInsets extends StatelessWidget {
  const RestoreKeyboardViewInsets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final raw = MediaQueryData.fromView(view);
    final mq = MediaQuery.of(context);
    if (raw.viewInsets == mq.viewInsets) {
      return child;
    }
    return MediaQuery(
      data: mq.copyWith(viewInsets: raw.viewInsets),
      child: child,
    );
  }
}

/// Scrollable auth-style layout: when the keyboard opens, the user can scroll
/// so fields at the bottom stay visible (uses [minHeight] = viewport height).
class KeyboardFriendlyScrollBody extends StatelessWidget {
  const KeyboardFriendlyScrollBody({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    this.alignment = const Alignment(0, 0.05),
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: alignment,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

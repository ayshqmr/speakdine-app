import 'package:flutter_test/flutter_test.dart';
import 'package:speak_dine/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeakDine());
    await tester.pump();
    expect(find.text('SpeakDine'), findsOneWidget);
  });
}

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:speak_dine/firebase_options.dart';
import 'package:speak_dine/view/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SpeakDine());
}

class SpeakDine extends StatelessWidget {
  const SpeakDine({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorSchemes.lightZinc.rose.copyWith(
          background: () => const Color(0xFFFFF1F2),
          primaryForeground: () => Colors.white,
          destructiveForeground: () => Colors.white,
        ),
        radius: 0.5,
        scaling: 1,
        typography: const Typography.geist(),
      ),
      home: const SplashView(),
    );
  }
}

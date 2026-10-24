import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/lock_screen.dart';
import 'screens/root.dart';
import 'services/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: C.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const AmanaApp());
}

class AmanaApp extends StatelessWidget {
  const AmanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..start(),
      child: Consumer<AppState>(
        builder: (context, s, _) {
          return MaterialApp(
            title: 'Amana AI',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            builder: (context, child) {
              // Urdu flips the whole layout. Any touch counts as activity for the idle lock.
              return Directionality(
                textDirection: s.ur ? TextDirection.rtl : TextDirection.ltr,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => s.touch(),
                  child: Stack(children: [
                    child ?? const SizedBox.shrink(),
                    if (s.boot == Boot.ready && s.locked) const Positioned.fill(child: LockScreen()),
                  ]),
                ),
              );
            },
            home: const RootScreen(),
          );
        },
      ),
    );
  }
}

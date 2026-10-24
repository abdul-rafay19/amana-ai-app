import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mark.dart';
import 'shell.dart';

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget body;
    switch (s.boot) {
      case Boot.loading:
        body = _Splash(key: const ValueKey('splash'), waking: s.waking);
        break;
      case Boot.failed:
        body = _Failed(key: const ValueKey('failed'));
        break;
      case Boot.ready:
        body = const HomeShell(key: ValueKey('home'));
        break;
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: body);
  }
}

class _Splash extends StatefulWidget {
  final bool waking;
  const _Splash({super.key, required this.waking});
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _in(double a, double b) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: Curves.easeOut));

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final nameIn = _in(0.55, 0.85);
    final tagIn = _in(0.72, 1.0);
    return Scaffold(
      backgroundColor: C.indigo,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.0,
            colors: [Color(0xFF3A4A94), C.indigo],
          ),
        ),
        child: Column(children: [
          const SafeArea(bottom: false, child: AjrakStrip(height: 12)),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedEmblem(animation: _c, size: 210),
                  const SizedBox(height: 26),
                  FadeTransition(
                    opacity: nameIn,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(nameIn),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(s.t('app_name'), style: T.display(s.ur, size: 46, color: C.white)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                          decoration: BoxDecoration(color: C.madder, borderRadius: BorderRadius.circular(10)),
                          child: Text('AI', style: T.number(size: 22, color: C.white, w: FontWeight.w800)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FadeTransition(
                    opacity: tagIn,
                    child: Text(s.t('tagline'),
                        textAlign: TextAlign.center,
                        style: T.body(s.ur, size: 15.5, color: const Color(0xFFD9DDEC))),
                  ),
                  const SizedBox(height: 34),
                  FadeTransition(
                    opacity: tagIn,
                    child: const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: C.white)),
                  ),
                  if (widget.waking) ...[
                    const SizedBox(height: 16),
                    Text(s.t('waking'),
                        textAlign: TextAlign.center,
                        style: T.body(s.ur, size: 13.5, color: const Color(0xFFD9DDEC))),
                  ],
                ]),
              ),
            ),
          ),
          const SafeArea(top: false, child: AjrakStrip(height: 12)),
        ]),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      backgroundColor: C.bg,
      body: Column(children: [
        const SafeArea(bottom: false, child: AjrakStrip(height: 14)),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AmCard(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_rounded, size: 46, color: C.madder),
                    const SizedBox(height: 12),
                    Text(s.t('conn_fail'),
                        textAlign: TextAlign.center, style: T.display(s.ur, size: 22)),
                    const SizedBox(height: 8),
                    Text(s.bootError ?? '',
                        textAlign: TextAlign.center, style: T.body(s.ur, color: C.mute)),
                    const SizedBox(height: 20),
                    AmButton(label: s.t('retry'), ur: s.ur, icon: Icons.refresh_rounded, onTap: () => s.start()),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

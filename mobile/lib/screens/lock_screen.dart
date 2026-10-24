import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pin.dart';

/// Full-screen PIN lock (Shared-Phone Safe Mode). The server also refuses data while locked.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  bool _wrong = false;
  bool _busy = false;
  int _wait = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _wait = context.read<AppState>().lockWait;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_wait > 0 && mounted) setState(() => _wait--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _digit(String d) async {
    if (_busy || _wait > 0 || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _wrong = false;
    });
    if (_pin.length == 4) {
      final s = context.read<AppState>();
      setState(() => _busy = true);
      final ok = await s.verifyPin(_pin);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin = '';
        _wrong = !ok;
        _wait = ok ? 0 : s.lockWait;
      });
    }
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    String msg = '';
    if (_wait > 0) {
      msg = s.t('lock_wait', {'s': _wait});
    } else if (_wrong) {
      msg = s.t('lock_wrong', {'n': s.attemptsLeft});
    }
    return Material(
      color: C.bg,
      child: Column(children: [
        const SafeArea(bottom: false, child: AjrakStrip(height: 12)),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: C.indigo),
                  child: const Icon(Icons.lock_rounded, color: C.white, size: 40),
                ),
                const SizedBox(height: 16),
                Text(s.t('lock_title'), style: T.display(ur, size: 26)),
                const SizedBox(height: 4),
                Text(s.t('lock_sub'), style: T.body(ur, size: 15, color: C.mute)),
                const SizedBox(height: 22),
                PinDots(filled: _pin.length, error: _wrong || _wait > 0),
                SizedBox(
                  height: 40,
                  child: Center(
                    child: Text(msg,
                        textAlign: TextAlign.center,
                        style: T.body(ur, size: 14, color: C.madder, w: FontWeight.w700)),
                  ),
                ),
                Keypad(onDigit: _digit, onBack: _back, enabled: !_busy && _wait == 0),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

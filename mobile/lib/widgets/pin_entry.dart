import 'package:flutter/material.dart';

import '../theme.dart';
import 'pin.dart';

/// Title + 4 dots + keypad. Calls onComplete when 4 digits are typed.
/// onComplete returns null on success, or an error message to show (the dots then reset).
class PinEntry extends StatefulWidget {
  final String title;
  final bool ur;
  final Future<String?> Function(String pin) onComplete;
  const PinEntry({super.key, required this.title, required this.ur, required this.onComplete});

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _pin = '';
  String? _err;
  bool _busy = false;

  Future<void> _digit(String d) async {
    if (_busy || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _err = null;
    });
    if (_pin.length == 4) {
      setState(() => _busy = true);
      final e = await widget.onComplete(_pin);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin = '';
        _err = e;
      });
    }
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.ur;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title,
          textAlign: TextAlign.center, style: T.display(ur, size: 18)),
      const SizedBox(height: 14),
      PinDots(filled: _pin.length, error: _err != null),
      SizedBox(
        height: 36,
        child: Center(
          child: Text(_err ?? '',
              textAlign: TextAlign.center,
              style: T.body(ur, size: 13.5, color: C.madder, w: FontWeight.w700)),
        ),
      ),
      Keypad(onDigit: _digit, onBack: _back, enabled: !_busy),
    ]);
  }
}

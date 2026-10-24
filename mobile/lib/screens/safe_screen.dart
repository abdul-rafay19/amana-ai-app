import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pin_entry.dart';
import '../widgets/segmented.dart';

class SafeScreen extends StatefulWidget {
  const SafeScreen({super.key});
  @override
  State<SafeScreen> createState() => _SafeScreenState();
}

class _SafeScreenState extends State<SafeScreen> {
  String? _first; // first PIN typed while setting up
  bool _learn = false;

  Future<String?> _setupStep(AppState s, String pin) async {
    if (_first == null) {
      setState(() => _first = pin);
      return null;
    }
    if (_first != pin) {
      setState(() => _first = null);
      return s.t('pin_mismatch');
    }
    final err = await s.setPin(pin);
    if (err == null && mounted) {
      setState(() => _first = null);
      s.flash(s.t('pin_ok'));
    }
    return err;
  }

  Future<void> _turnOff(AppState s) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: SafeArea(
          child: SingleChildScrollView(
            child: PinEntry(
              title: s.t('pin_off_title'),
              ur: s.ur,
              onComplete: (pin) async {
                final e = await s.turnOffPin(pin);
                if (e == null && ctx.mounted) Navigator.of(ctx).pop();
                return e;
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _wipe(AppState s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.white,
        content: Text(s.t('delete_confirm'), style: T.body(s.ur, size: 15.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('cancel'), style: T.body(s.ur, w: FontWeight.w700, color: C.mute)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.t('delete'), style: T.body(s.ur, w: FontWeight.w800, color: C.madder)),
          ),
        ],
      ),
    );
    if (yes == true) {
      await s.wipeAll();
      s.flash(s.t('sb_wiped'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    const options = [30, 60, 120, 300];
    final idx = options.indexOf(s.lockSeconds);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(s.t('safe_title'), style: T.display(ur, size: 22)),
        const SizedBox(height: 12),
        if (s.hasPin)
          AmCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: C.leafBg),
                  child: const Icon(Icons.shield_rounded, color: C.leaf),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.t('safe_on'), style: T.display(ur, size: 18, color: C.leaf))),
              ]),
              const SizedBox(height: 16),
              Text(s.t('autolock'), style: T.body(ur, size: 13.5, w: FontWeight.w600, color: C.mute)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Segmented(
                  labels: [for (final o in options) '${o}s'],
                  index: idx < 0 ? 1 : idx,
                  onChanged: (i) => s.setLockSeconds(options[i]),
                ),
              ),
              const SizedBox(height: 16),
              AmButton(
                label: s.t('lock_now'),
                ur: ur,
                icon: Icons.lock_rounded,
                onTap: () => s.lockNow(),
              ),
              const SizedBox(height: 8),
              AmButton(
                label: s.t('pin_off'),
                ur: ur,
                kind: BtnKind.outline,
                onTap: () => _turnOff(s),
              ),
            ]),
          )
        else ...[
          AmCard(
            color: C.amberBg,
            border: C.amberBg,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: C.amber),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('safe_off'), style: T.body(ur, size: 14.5, w: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 12),
          AmCard(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: PinEntry(
              key: ValueKey(_first == null ? 'pin-a' : 'pin-b'),
              title: _first == null ? s.t('pin_set_title') : s.t('pin_again'),
              ur: ur,
              onComplete: (pin) => _setupStep(s, pin),
            ),
          ),
        ],
        const SizedBox(height: 14),

        // ---- "why this matters": limits + notification preview, collapsed by default
        AmCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _learn = !_learn),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: C.indigo2),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.t('learn_more'), style: T.body(ur, size: 16, w: FontWeight.w700))),
                  AnimatedRotation(
                    turns: _learn ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded, color: C.mute),
                  ),
                ]),
              ),
            ),
            if (_learn)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final x in trList('limits', s.lang))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Icon(Icons.circle, size: 6, color: C.indigo2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(x, style: T.body(ur, size: 14.5))),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  Text(s.t('notif_title'), style: T.display(ur, size: 16)),
                  const SizedBox(height: 10),
                  _Notif(
                    label: s.t('notif_bad'),
                    title: 'Amana',
                    body: 'Order AM-2610-001: payment short by Rs 1,500',
                    good: false,
                  ),
                  const SizedBox(height: 10),
                  _Notif(
                    label: s.t('notif_good'),
                    title: ur ? 'امانہ' : 'Amana',
                    body: ur ? 'آپ کے لیے نیا پیغام ہے۔ اپنے PIN سے کھولیں۔' : 'You have a new update. Open with your PIN.',
                    good: true,
                  ),
                  const SizedBox(height: 6),
                  Muted(s.t('notif_note'), ur: ur),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 22),
        const StitchDivider(),
        const SizedBox(height: 16),
        AmButton(
          label: s.t('sb_wipe'),
          ur: ur,
          kind: BtnKind.danger,
          icon: Icons.delete_outline_rounded,
          onTap: () => _wipe(s),
        ),
      ],
    );
  }
}

class _Notif extends StatelessWidget {
  final String label;
  final String title;
  final String body;
  final bool good;
  const _Notif({required this.label, required this.title, required this.body, required this.good});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = good ? C.leaf : C.madder;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Pill(label, bg: good ? C.leafBg : C.madderBg, fg: c, ur: s.ur, icon: good ? Icons.shield_rounded : Icons.visibility_rounded),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: C.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.line),
          boxShadow: const [BoxShadow(color: C.shadow, blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: C.indigo, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: const Text('🧵', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.body(s.ur, size: 14, w: FontWeight.w800)),
              Text(body, style: T.body(s.ur, size: 13.5, color: C.mute)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

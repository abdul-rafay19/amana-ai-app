import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Stage "confirmed": the agreement is saved; now she enters what she received.
class SavedView extends StatefulWidget {
  const SavedView({super.key});
  @override
  State<SavedView> createState() => _SavedViewState();
}

class _SavedViewState extends State<SavedView> {
  final _received = TextEditingController();
  final _advance = TextEditingController();
  final _deduct = TextEditingController();
  final _note = TextEditingController();
  bool _partial = false;
  bool _more = false; // optional fields
  bool _recDetails = false; // fingerprint etc.
  String? _proof;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _received.dispose();
    _advance.dispose();
    _deduct.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await _picker.pickImage(source: src, maxWidth: 1800, imageQuality: 80);
      if (x != null && mounted) setState(() => _proof = x.path);
    } catch (_) {
      if (mounted) {
        final s = context.read<AppState>();
        s.flash(s.t('err_generic'), error: true);
      }
    }
  }

  Future<void> _submit() async {
    final s = context.read<AppState>();
    final rec = parseAmount(_received.text);
    if (rec == null || rec < 0) {
      s.flash(s.t('pay_zero'), error: true);
      return;
    }
    final adv = _advance.text.trim().isEmpty ? 0.0 : parseAmount(_advance.text);
    final ded = _deduct.text.trim().isEmpty ? 0.0 : parseAmount(_deduct.text);
    if (adv == null || ded == null || adv < 0 || ded < 0) {
      s.flash(s.t('enter_number'), error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    await s.checkPayment(
      received: rec,
      advance: adv,
      deductions: ded,
      partial: _partial,
      note: _note.text.trim(),
      proofPath: _proof,
    );
  }

  Widget _toggleRow(AppState s, String label, bool open, VoidCallback onTap, IconData icon) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(icon, color: C.indigo2, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: T.body(s.ur, size: 15.5, w: FontWeight.w700, color: C.indigo))),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more_rounded, color: C.mute),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final rec = s.record ?? <String, dynamic>{};
    final data = rec.m('data');
    final integ = rec.m('integrity');
    final ok = integ.isEmpty ? true : integ.b('ok');

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ---- saved record (short)
          AmCard(
            child: Column(children: [
              const Seal(),
              const SizedBox(height: 10),
              Text(s.t('rec_saved'), style: T.display(ur, size: 22)),
              const SizedBox(height: 4),
              Text('${rec.s('order_no') ?? ''}  ·  ${fmtRs(data.n('expected_total'))}',
                  style: T.body(false, size: 15, w: FontWeight.w700, color: C.mute)),
              const SizedBox(height: 10),
              IntegrityBadge(
                ok: ok,
                ur: ur,
                text: ok ? s.t('int_ok') : s.t('int_bad', {'f': integ.l('changed_fields').join(', ')}),
              ),
              const SizedBox(height: 4),
              _toggleRow(s, s.t('details'), _recDetails, () => setState(() => _recDetails = !_recDetails),
                  Icons.fingerprint_rounded),
              if (_recDetails)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.t('rec_fp'), style: T.body(ur, size: 12.5, color: C.mute, w: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(shortHash(rec.s('hash'), 24),
                        style: T.body(false, size: 14, w: FontWeight.w700, color: C.indigo)),
                    const SizedBox(height: 6),
                    Text(rec.b('first') ? s.t('rec_first') : s.t('rec_chain'),
                        style: T.body(ur, size: 12.5, color: C.mute)),
                    const SizedBox(height: 6),
                    Text(s.t('rec_honest'), style: T.body(ur, size: 12.5, color: C.mute)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),

          if (s.blocked) ...[
            AmCard(
              color: C.madderBg,
              border: C.madder,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.gpp_bad_outlined, color: C.madder),
                const SizedBox(width: 10),
                Expanded(child: Text(s.t('blocked'), style: T.body(ur, size: 14.5, w: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // ---- payment form: one required field, the rest tucked away
          AmCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('pay_title'), style: T.display(ur, size: 20)),
              const SizedBox(height: 4),
              Text('${s.t('pay_expected')}: ${fmtRs(data.n('expected_total'))}',
                  style: T.body(ur, size: 14, color: C.mute, w: FontWeight.w600)),
              const SizedBox(height: 14),
              AmField(
                controller: _received,
                label: s.t('pay_received'),
                ur: ur,
                prefix: 'Rs ',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 4),
              _toggleRow(s, s.t('optional_details'), _more, () => setState(() => _more = !_more),
                  Icons.tune_rounded),
              if (_more) ...[
                AmField(
                  controller: _advance,
                  label: s.t('pay_adv'),
                  ur: ur,
                  prefix: 'Rs ',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                AmField(
                  controller: _deduct,
                  label: s.t('pay_ded'),
                  ur: ur,
                  prefix: 'Rs ',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(s.t('pay_partial'), style: T.body(ur, size: 15.5, w: FontWeight.w600))),
                  Switch(value: _partial, onChanged: (v) => setState(() => _partial = v)),
                ]),
                const SizedBox(height: 8),
                AmField(controller: _note, label: s.t('pay_note'), ur: ur, maxLength: 300),
                const SizedBox(height: 14),
                Text(s.t('pay_proof'), style: T.body(ur, size: 13.5, w: FontWeight.w600, color: C.mute)),
                const SizedBox(height: 8),
                if (_proof == null)
                  Row(children: [
                    Expanded(
                      child: AmButton(
                          label: s.t('take_photo'),
                          ur: ur,
                          kind: BtnKind.outline,
                          icon: Icons.photo_camera_outlined,
                          onTap: () => _pick(ImageSource.camera)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AmButton(
                          label: s.t('pick_photo'),
                          ur: ur,
                          kind: BtnKind.outline,
                          icon: Icons.photo_library_outlined,
                          onTap: () => _pick(ImageSource.gallery)),
                    ),
                  ])
                else
                  Row(children: [
                    Expanded(
                        child: Pill(s.t('photo_added'),
                            bg: C.leafBg, fg: C.leaf, icon: Icons.check_circle_rounded, ur: ur)),
                    TextButton(
                      onPressed: () => setState(() => _proof = null),
                      child: Text(s.t('remove'), style: T.body(ur, size: 14, w: FontWeight.w700, color: C.madder)),
                    ),
                  ]),
              ],
              const SizedBox(height: 16),
              AmButton(
                label: s.t('pay_btn'),
                ur: ur,
                icon: Icons.fact_check_outlined,
                busy: s.busy,
                onTap: _submit,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

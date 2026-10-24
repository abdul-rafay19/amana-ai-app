import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

class ReviewView extends StatefulWidget {
  const ReviewView({super.key});
  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  late final TextEditingController _target;
  bool _open = false;
  bool _details = false;

  @override
  void initState() {
    super.initState();
    final m = context.read<AppState>().minHourly;
    _target = TextEditingController(text: fmtNum(m > 0 ? m : 150));
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final c = s.calc;
    if (c == null) return const SizedBox.shrink();

    final unk = s.t('r_unknown');
    final net = c.n('net_after_expenses');
    final hourly = c.n('hourly_net');
    final hours = c.n('estimated_hours');
    final costs = c.n('material_expenses');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        // ---- hero numbers
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [C.indigo, C.indigo2],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('review_title'),
                style: T.body(ur, size: 13.5, w: FontWeight.w700, color: const Color(0xFFD9DDEC))),
            const SizedBox(height: 10),
            Text(s.t('r_expected'),
                style: T.body(ur, size: 13, color: const Color(0xFFD9DDEC))),
            const SizedBox(height: 2),
            Text(fmtRs(c.n('expected_total')), style: T.number(size: 38, color: C.white)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _kpi(s, s.t('r_net'), net == null ? unk : fmtRs(net))),
              const SizedBox(width: 10),
              Expanded(child: _kpi(s, s.t('r_hourly'), hourly == null ? '–' : fmtRs(hourly))),
            ]),
          ]),
        ),
        const SizedBox(height: 12),

        // ---- details (collapsed by default so the screen stays calm)
        AmCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _details = !_details),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.receipt_long_outlined, color: C.indigo2),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(_details ? s.t('hide_details') : s.t('show_details'),
                          style: T.body(ur, size: 16, w: FontWeight.w700))),
                  AnimatedRotation(
                    turns: _details ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded, color: C.mute),
                  ),
                ]),
              ),
            ),
            if (_details)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Ledger(ur: ur, rows: [
                    LRow('${s.t('r_expected')} (${fmtNum(c.n('quantity'))} × ${fmtRs(c.n('rate_per_piece'))})',
                        fmtRs(c.n('expected_total'))),
                    LRow(s.t('r_costs'), costs == null ? unk : fmtRs(costs), costs == null ? LKind.dim : LKind.normal),
                    LRow(s.t('r_net'), net == null ? unk : fmtRs(net), net == null ? LKind.dim : LKind.normal),
                    LRow(s.t('r_hours'), (hours == null || hours == 0) ? unk : fmtNum(hours),
                        (hours == null || hours == 0) ? LKind.dim : LKind.normal),
                    const LRow.rule(),
                    LRow(s.t('r_hourly'), hourly == null ? '–' : fmtRs(hourly), LKind.big),
                  ]),
                  const SizedBox(height: 10),
                  Text(s.t('estimate_note'), style: T.body(ur, size: 12.5, color: C.mute)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        if ((s.explain ?? '').isNotEmpty) AiNote(label: s.t('note_ai'), text: s.explain!, ur: ur),
        const SizedBox(height: 12),

        // ---- flags
        AmCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('flags_title'), style: T.display(ur, size: 17)),
            const SizedBox(height: 10),
            for (final f in s.flags)
              if (f is Map)
                FlagTile(
                  level: (f['level'] ?? 'amber').toString(),
                  text: (f[ur ? 'ur' : 'en'] ?? f['en'] ?? '').toString(),
                  ur: ur,
                ),
          ]),
        ),
        const SizedBox(height: 12),

        // ---- counteroffer
        _counter(s),
        const SizedBox(height: 16),

        Text(s.t('confirm_note'), textAlign: TextAlign.center, style: T.body(ur, size: 13.5, color: C.mute)),
        const SizedBox(height: 10),
        AmButton(
          label: s.t('btn_confirm'),
          ur: ur,
          icon: Icons.verified_rounded,
          busy: s.busy,
          onTap: () => s.confirmAgreement(),
        ),
        const SizedBox(height: 10),
        AmButton(
          label: s.t('btn_edit'),
          ur: ur,
          kind: BtnKind.outline,
          icon: Icons.edit_outlined,
          onTap: s.busy ? null : () => s.backToChat(),
        ),
      ],
    );
  }

  Widget _kpi(AppState s, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            maxLines: 2,
            style: T.body(s.ur, size: 12, color: const Color(0xFFD9DDEC), height: 1.25)),
        const SizedBox(height: 4),
        Text(value,
            style: hasUrdu(value) || RegExp(r'[A-Za-z]{4,}').hasMatch(value)
                ? T.body(s.ur, size: 15, w: FontWeight.w700, color: C.white)
                : T.number(size: 21, color: C.white)),
      ]),
    );
  }

  Widget _counter(AppState s) {
    final ur = s.ur;
    final co = s.counter;
    return AmCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.handshake_outlined, color: C.indigo2),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('counter_title'), style: T.display(ur, size: 16.5))),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded, color: C.mute),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AmField(
                      controller: _target,
                      label: s.t('counter_target'),
                      ur: ur,
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 10),
                    AmButton(
                      label: s.t('counter_btn'),
                      ur: ur,
                      kind: BtnKind.secondary,
                      busy: s.busy,
                      onTap: () {
                        final hours = s.calc?.n('estimated_hours');
                        if (hours == null || hours == 0) {
                          s.flash(s.t('need_hours'), error: true);
                          return;
                        }
                        final v = parseAmount(_target.text);
                        if (v == null || v <= 0) {
                          s.flash(s.t('pay_zero'), error: true);
                          return;
                        }
                        FocusScope.of(context).unfocus();
                        s.makeCounter(v);
                      },
                    ),
                    if (co != null && co['error'] == null) ...[
                      const SizedBox(height: 12),
                      if (co.b('already_meets_target'))
                        _info(s.t('counter_ok'), C.leafBg, C.leaf)
                      else ...[
                        _info(
                            s.t('counter_result', {
                              't': fmtRs(co.n('target_hourly')),
                              'r': fmtRs(co.n('suggested_rate')),
                              'c': fmtRs(co.n('current_rate')),
                            }),
                            C.tint,
                            C.indigo),
                        const SizedBox(height: 10),
                        Muted(s.t('counter_msg'), ur: ur),
                        const SizedBox(height: 6),
                        _msgBox(s, co.s('message') ?? ''),
                      ],
                    ],
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _info(String text, Color bg, Color fg) {
    final ur = context.read<AppState>().ur;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, textDirection: dirOf(text), style: T.body(ur || hasUrdu(text), size: 14.5, color: fg, w: FontWeight.w600)),
    );
  }

  Widget _msgBox(AppState s, String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(msg, textDirection: dirOf(msg), style: T.body(hasUrdu(msg), size: 15)),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: msg));
              s.flash(s.t('copied'));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(s.t('copy'), style: T.body(s.ur, size: 14, w: FontWeight.w700, color: C.indigo2)),
          ),
        ),
      ]),
    );
  }
}

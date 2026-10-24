import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

class ReportView extends StatefulWidget {
  const ReportView({super.key});
  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  late final TextEditingController _msg;

  @override
  void initState() {
    super.initState();
    _msg = TextEditingController(text: context.read<AppState>().msgText);
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  String _summary(AppState s) {
    final rep = s.report ?? <String, dynamic>{};
    final c = rep.m('comparison');
    final d = s.record?.m('data') ?? <String, dynamic>{};
    return [
      'Amana AI payment summary for ${rep.s('order_no')}',
      'Item: ${fmtNum(d.n('quantity'))} x ${d.s('item') ?? 'pieces'} at ${fmtRs(d.n('rate_per_piece'))} per piece',
      'Agreed total: ${fmtRs(c.n('expected'))}',
      'Advance paid earlier: ${fmtRs(c.n('advance_paid'))}',
      'Agreed deductions: ${fmtRs(c.n('agreed_deductions'))}',
      'Received now: ${fmtRs(c.n('received'))}',
      'Difference: ${fmtRs(c.n('difference'))}',
      'Not explained: ${fmtRs(c.n('unexplained'))}',
      'Status: ${c.s('status')}',
      'Agreement fingerprint: ${rep.s('agreement_hash')}',
      'Note: the fingerprint shows whether the record changed after saving; it does not prove the information was true.',
    ].join('\n');
  }

  Future<void> _openWhatsApp(String url) async {
    final s = context.read<AppState>();
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) s.flash(s.t('err_generic'), error: true);
    } catch (_) {
      s.flash(s.t('err_generic'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final rep = s.report;
    if (rep == null) return const SizedBox.shrink();
    final c = rep.m('comparison');
    final status = c.s('status') ?? 'match';
    final unx = c.n('unexplained') ?? 0;
    final integ = rep.m('integrity');
    final integOk = integ.isEmpty ? true : integ.b('ok');
    final missing = rep.l('missing_info');
    final hasDraft = (rep.s('draft_message') ?? '').isNotEmpty || s.msgText.isNotEmpty;

    Color bg;
    Color fg;
    IconData ic;
    switch (status) {
      case 'match':
      case 'explained':
        bg = C.leafBg;
        fg = C.leaf;
        ic = Icons.check_circle_rounded;
        break;
      case 'over':
        bg = C.amberBg;
        fg = C.amber;
        ic = Icons.info_rounded;
        break;
      default:
        bg = C.madderBg;
        fg = C.madder;
        ic = Icons.error_rounded;
    }
    final showAmount = status == 'short' || status == 'partial_pending' || status == 'over';

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ---- status banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: fg, width: 1.4),
            ),
            child: Row(children: [
              Icon(ic, color: fg, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.t('st_$status'), style: T.display(ur, size: 20, color: fg)),
                  if (showAmount) ...[
                    const SizedBox(height: 2),
                    Text(fmtRs(unx.abs()), style: T.number(size: 32, color: fg)),
                    Text(s.t('rep_unx'), style: T.body(ur, size: 13, color: fg, w: FontWeight.w600)),
                  ],
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ---- ledger
          AmCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.t('rep_title')} · ${rep.s('order_no') ?? ''}', style: T.display(ur, size: 17)),
              const SizedBox(height: 10),
              Ledger(ur: ur, rows: [
                LRow(s.t('pay_expected'), fmtRs(c.n('expected'))),
                LRow(s.t('rep_adv'), fmtRs(c.n('advance_paid')), LKind.dim),
                LRow(s.t('rep_ded'), fmtRs(c.n('agreed_deductions')), LKind.dim),
                LRow(s.t('rep_recv'), fmtRs(c.n('received'))),
                const LRow.rule(),
                LRow(s.t('rep_diff'), fmtRs(c.n('difference')), LKind.big),
                LRow(s.t('rep_unx'), fmtRs(c.n('unexplained')), unx > 0 ? LKind.warn : LKind.good),
              ]),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: IntegrityBadge(
                  ok: integOk,
                  ur: ur,
                  text: integOk
                      ? s.t('int_ok')
                      : s.t('int_bad', {'f': integ.l('changed_fields').join(', ')}),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          if ((rep.s('explanation') ?? '').isNotEmpty)
            AiNote(label: s.t('note_ai'), text: rep.s('explanation')!, ur: ur),
          const SizedBox(height: 12),

          // ---- what we still don't know
          if (missing.isNotEmpty) ...[
            AmCard(
              color: C.amberBg,
              border: C.amberBg,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('rep_missing'), style: T.display(ur, size: 17)),
                const SizedBox(height: 8),
                for (final m in missing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(Icons.help_outline_rounded, size: 18, color: C.amber),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('$m',
                              textDirection: dirOf('$m'),
                              style: T.body(hasUrdu('$m') || ur, size: 14.5))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ---- message
          if (hasDraft) _messageBlock(s) else Muted(s.t('rep_nomsg'), ur: ur),
          const SizedBox(height: 16),

          Row(children: [
            Expanded(
              child: AmButton(
                label: s.t('copy_summary'),
                ur: ur,
                kind: BtnKind.outline,
                icon: Icons.ios_share_rounded,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: _summary(s)));
                  s.flash(s.t('copied'));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AmButton(
                label: s.t('rep_new'),
                ur: ur,
                kind: BtnKind.secondary,
                icon: Icons.add_rounded,
                onTap: () => s.newOrder(),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _messageBlock(AppState s) {
    final ur = s.ur;
    return AmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('rep_draft'), style: T.display(ur, size: 17)),
        const SizedBox(height: 10),
        if (s.follow == null) ...[
          AmField(
            controller: _msg,
            label: s.t('rep_edit'),
            ur: ur,
            maxLines: 6,
            maxLength: 1500,
            onChanged: (v) => s.setMsgText(v),
          ),
          const SizedBox(height: 12),
          AmButton(
            label: s.t('rep_approve'),
            ur: ur,
            icon: Icons.thumb_up_alt_outlined,
            onTap: () => s.approveMessage(_msg.text),
          ),
          const SizedBox(height: 8),
          AmButton(
            label: s.t('rep_dismiss'),
            ur: ur,
            kind: BtnKind.outline,
            onTap: () => s.dismissMessage(_msg.text),
          ),
        ] else if (s.follow == 'approved') ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.line),
            ),
            child: Text(s.msgText, textDirection: dirOf(s.msgText), style: T.body(hasUrdu(s.msgText), size: 15)),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.leafBg, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_rounded, color: C.leaf, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(s.t('rep_approved'), style: T.body(ur, size: 14, color: C.leaf, w: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 12),
          AmButton(
            label: s.t('open_wa'),
            ur: ur,
            icon: Icons.chat_rounded,
            onTap: s.waUrl == null ? null : () => _openWhatsApp(s.waUrl!),
          ),
          const SizedBox(height: 8),
          AmButton(
            label: s.t('copy'),
            ur: ur,
            kind: BtnKind.outline,
            icon: Icons.copy_rounded,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: s.msgText));
              s.flash(s.t('copied'));
            },
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(12)),
            child: Text(s.t('rep_dismissed'), style: T.body(ur, size: 14.5, w: FontWeight.w600)),
          ),
      ]),
    );
  }
}

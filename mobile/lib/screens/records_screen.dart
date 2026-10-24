import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  String? _chainMsg;
  bool _chainOk = true;
  bool _checking = false;

  Future<void> _verify() async {
    final s = context.read<AppState>();
    setState(() => _checking = true);
    final r = await s.verifyChain();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (r == null) {
        _chainMsg = null;
        return;
      }
      _chainOk = r.b('ok');
      if (_chainOk) {
        _chainMsg = s.t('chain_ok', {'n': r.n('length')?.toInt() ?? 0});
      } else {
        final probs = r
            .l('problems')
            .whereType<Map>()
            .map((p) => '${p['order_no']} v${p['version']}: ${p['reason']}')
            .join('; ');
        _chainMsg = s.t('chain_bad', {'p': probs});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final data = s.recordsData;
    final orders = data?.l('orders') ?? <dynamic>[];
    final sum = data?.m('summary') ?? <String, dynamic>{};

    Widget body;
    if (data == null) {
      body = s.recordsLoading
          ? const Center(child: CircularProgressIndicator(color: C.indigo))
          : Center(
              child: AmButton(
                  label: s.t('retry'), ur: ur, expand: false, onTap: () => s.loadRecords()));
    } else if (orders.isEmpty) {
      body = ListView(padding: const EdgeInsets.all(16), children: [
        Text(s.t('records_title'), style: T.display(ur, size: 22)),
        const SizedBox(height: 12),
        AmCard(
          child: Column(children: [
            const Icon(Icons.receipt_long_outlined, size: 44, color: C.indigo2),
            const SizedBox(height: 10),
            Text(s.t('rec_empty'), textAlign: TextAlign.center, style: T.body(ur, size: 15)),
            const SizedBox(height: 14),
            AmButton(label: s.t('btn_sample'), ur: ur, onTap: () => s.loadSample()),
          ]),
        ),
      ]);
    } else {
      body = RefreshIndicator(
        color: C.indigo,
        onRefresh: () => s.loadRecords(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(s.t('records_title'), style: T.display(ur, size: 22)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Kpi(label: s.t('sum_orders'), value: '${sum.n('orders')?.toInt() ?? 0}')),
              const SizedBox(width: 10),
              Expanded(child: _Kpi(label: s.t('sum_expected'), value: fmtRs(sum.n('expected')))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Kpi(label: s.t('sum_received'), value: fmtRs(sum.n('received')))),
              const SizedBox(width: 10),
              Expanded(
                  child: _Kpi(
                      label: s.t('sum_open'),
                      value: fmtRs(sum.n('open')),
                      accent: (sum.n('open') ?? 0) > 0 ? C.madder : C.leaf)),
            ]),
            const SizedBox(height: 14),
            AmButton(
              label: s.t('btn_verify'),
              ur: ur,
              kind: BtnKind.outline,
              icon: Icons.fact_check_outlined,
              busy: _checking,
              onTap: _verify,
            ),
            if (_chainMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _chainOk ? C.leafBg : C.madderBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_chainOk ? Icons.verified_rounded : Icons.warning_amber_rounded,
                      color: _chainOk ? C.leaf : C.madder, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_chainMsg!,
                          style: T.body(ur, size: 14.5, w: FontWeight.w600, color: _chainOk ? C.leaf : C.madder))),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            for (final o in orders)
              if (o is Map)
                _OrderCard(
                  key: ValueKey('${o['order_no']}-${o['version']}-${(o['integrity'] as Map?)?['ok']}'),
                  order: Map<String, dynamic>.from(o),
                ),
          ],
        ),
      );
    }
    return body;
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _Kpi({required this.label, required this.value, this.accent = C.indigo});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return AmCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: T.number(size: 22, color: accent)),
        const SizedBox(height: 3),
        Text(label, style: T.body(s.ur, size: 12.5, color: C.mute, w: FontWeight.w600)),
      ]),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  const _OrderCard({super.key, required this.order});
  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = !widget.order.m('integrity').b('ok'); // a changed record opens by itself
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final o = widget.order;
    final d = o.m('data');
    final integ = o.m('integrity');
    final ok = integ.b('ok');
    final src = d.m('sources');
    final pays = o.l('payments');

    final fields = <(String, String)>[
      ('item', 'f_item'),
      ('quantity', 'f_quantity'),
      ('rate_per_piece', 'f_rate'),
      ('material_expenses', 'f_materials'),
      ('estimated_hours', 'f_hours'),
      ('deadline_days', 'f_deadline'),
      ('payment_terms', 'f_terms'),
    ];
    final rows = <LRow>[];
    for (final f in fields) {
      final v = d[f.$1];
      if (v == null) continue;
      final shown = (f.$1 == 'rate_per_piece' || f.$1 == 'material_expenses')
          ? fmtRs(v is num ? v : num.tryParse('$v'))
          : (v is num ? fmtNum(v) : '$v');
      final tag = src[f.$1] == 'reported_by_worker' ? s.t('src_worker') : s.t('src_calc');
      rows.add(LRow('${s.t(f.$2)} ($tag)', shown));
    }
    rows.add(const LRow.rule());
    rows.add(LRow(s.t('r_expected'), fmtRs(d.n('expected_total')), LKind.big));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AmCard(
        padding: EdgeInsets.zero,
        border: ok ? C.line : C.madder,
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(o.s('order_no') ?? '', style: T.number(size: 16, color: C.indigo)),
                      if (o.b('is_sample')) ...[
                        const SizedBox(width: 8),
                        Pill(s.t('sample_tag'), ur: ur),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        '${fmtNum(d.n('quantity'))} × ${d.s('item') ?? '—'} · ${fmtRs(d.n('expected_total'))}',
                        style: T.body(ur, size: 13.5, color: C.mute, w: FontWeight.w600)),
                  ]),
                ),
                Icon(ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
                    color: ok ? C.leaf : C.madder),
                const SizedBox(width: 6),
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
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const StitchDivider(),
                      const SizedBox(height: 10),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: IntegrityBadge(
                          ok: ok,
                          ur: ur,
                          text: ok
                              ? s.t('int_ok')
                              : s.t('int_bad', {'f': integ.l('changed_fields').join(', ')}),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('${s.t('rec_fp')}: ${shortHash(o.s('hash'), 20)}',
                          style: T.body(false, size: 12.5, color: C.mute)),
                      Text(o.b('first') ? s.t('rec_first') : s.t('rec_chain'),
                          style: T.body(ur, size: 12.5, color: C.mute)),
                      const SizedBox(height: 10),
                      Ledger(ur: ur, rows: rows),
                      const SizedBox(height: 12),
                      Text(s.t('pay_hist'), style: T.display(ur, size: 15.5)),
                      const SizedBox(height: 6),
                      if (pays.isEmpty)
                        Muted(s.t('no_pay'), ur: ur)
                      else
                        for (final p in pays)
                          if (p is Map)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '${dateOf(p['created_at']?.toString())}: ${fmtRs(p['received'] is num ? p['received'] as num : null)} · '
                                '${s.t('st_${p['status']}')} · ${shortHash(p['hash']?.toString())}',
                                style: T.body(ur, size: 13.5, color: C.ink),
                              ),
                            ),
                      const SizedBox(height: 12),
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(s.t('demo_tools'),
                              style: T.body(ur, size: 13.5, w: FontWeight.w800, color: C.mute)),
                          children: [
                            Row(children: [
                              Expanded(
                                child: AmButton(
                                  label: s.t('btn_tamper'),
                                  ur: ur,
                                  kind: BtnKind.danger,
                                  onTap: () => s.tamper(o.s('order_no') ?? ''),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AmButton(
                                  label: s.t('btn_restore'),
                                  ur: ur,
                                  kind: BtnKind.outline,
                                  onTap: ok ? null : () => s.restore(o.s('order_no') ?? ''),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Text(s.t('tamper_note'), style: T.body(ur, size: 12.5, color: C.mute)),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

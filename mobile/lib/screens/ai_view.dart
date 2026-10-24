import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Transparency panel: every model call and tool call the agents made in this session.
class AiViewScreen extends StatelessWidget {
  const AiViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final ai = s.trace.where((e) => e['kind'] == 'ai').length;
    final code = s.trace.where((e) => e['kind'] == 'code').length;
    final checks = s.trace.where((e) => e['kind'] == 'check').length;
    final events = s.trace.reversed.toList();

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(children: [
        Container(
          color: C.white,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: C.indigo),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(child: Text(s.t('ai_view'), style: T.display(ur, size: 22))),
                Pill(s.aiMode == 'ai' ? 'AI' : 'OFFLINE',
                    bg: s.aiMode == 'ai' ? C.leafBg : C.amberBg,
                    fg: s.aiMode == 'ai' ? C.leaf : C.amber),
              ]),
            ),
          ),
        ),
        const AjrakStrip(height: 9),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  Row(children: [
                    Expanded(child: _count(s, s.t('ai_calls'), ai, C.indigo2)),
                    const SizedBox(width: 10),
                    Expanded(child: _count(s, s.t('code_calls'), code, C.leaf)),
                    const SizedBox(width: 10),
                    Expanded(child: _count(s, s.t('checks'), checks, C.madder)),
                  ]),
                  const SizedBox(height: 14),
                  AmCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t('who_title'), style: T.display(ur, size: 17)),
                      const SizedBox(height: 10),
                      _who(s, Icons.auto_awesome, C.indigo2, s.t('who_ai')),
                      _who(s, Icons.calculate_rounded, C.leaf, s.t('who_code')),
                      _who(s, Icons.touch_app_rounded, C.madder, s.t('who_human')),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Text(s.t('trace_title'), style: T.display(ur, size: 18)),
                  const SizedBox(height: 2),
                  Muted(s.t('audit_note'), ur: ur),
                  const SizedBox(height: 10),
                  if (events.isEmpty)
                    AmCard(child: Text(s.t('no_trace'), style: T.body(ur, color: C.mute)))
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: C.dark, borderRadius: BorderRadius.circular(16)),
                      child: Column(children: [
                        for (final e in events) _Event(e: e),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _count(AppState s, String label, int n, Color c) {
    return AmCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n', style: T.number(size: 26, color: c)),
        const SizedBox(height: 2),
        Text(label, style: T.body(s.ur, size: 12.5, color: C.mute, w: FontWeight.w600)),
      ]),
    );
  }

  Widget _who(AppState s, IconData ic, Color c, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ic, size: 20, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: T.body(s.ur, size: 14.5))),
      ]),
    );
  }
}

class _Event extends StatelessWidget {
  final Map<String, dynamic> e;
  const _Event({required this.e});

  String _short(dynamic v, [int max = 160]) {
    if (v == null) return '';
    String t;
    try {
      t = v is String ? v : jsonEncode(v);
    } catch (_) {
      t = '$v';
    }
    return t.length > max ? '${t.substring(0, max)}…' : t;
  }

  @override
  Widget build(BuildContext context) {
    final kind = e.s('kind') ?? 'code';
    final ok = e['ok'] != false;
    Color kc;
    String klabel;
    switch (kind) {
      case 'ai':
        kc = const Color(0xFF9FB0FF);
        klabel = 'AI';
        break;
      case 'check':
        kc = const Color(0xFFFF9FB0);
        klabel = 'CHECK';
        break;
      default:
        kc = const Color(0xFF7FD8AE);
        klabel = 'CODE';
    }
    final args = _short(e['args']);
    final result = _short(e['result']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2050),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${e['n']}', style: T.body(false, size: 12, color: const Color(0xFF8E96C8), w: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: kc, borderRadius: BorderRadius.circular(6)),
            child: Text(klabel, style: T.body(false, size: 10.5, w: FontWeight.w900, color: C.dark)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${e['agent']} · ${e['tool']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.body(false, size: 13.5, color: C.white, w: FontWeight.w700)),
          ),
          Text('${e['ms'] ?? 0} ms', style: T.body(false, size: 11.5, color: const Color(0xFF8E96C8))),
          const SizedBox(width: 6),
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 16, color: ok ? const Color(0xFF7FD8AE) : const Color(0xFFFF9FB0)),
        ]),
        if (args.isNotEmpty && args != '{}') ...[
          const SizedBox(height: 6),
          Text('in: $args', style: T.body(false, size: 11.5, color: const Color(0xFFB9C0E8), height: 1.3)),
        ],
        if (result.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('out: $result', style: T.body(false, size: 11.5, color: const Color(0xFFB9C0E8), height: 1.3)),
        ],
      ]),
    );
  }
}

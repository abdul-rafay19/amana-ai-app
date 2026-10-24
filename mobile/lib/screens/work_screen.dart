import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import 'chat_view.dart';
import 'report_view.dart';
import 'review_view.dart';
import 'saved_view.dart';

/// The worker journey: describe -> review -> record -> payment -> report.
class WorkScreen extends StatelessWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget body;
    switch (s.stage) {
      case 'review':
        body = const ReviewView(key: ValueKey('review'));
        break;
      case 'confirmed':
        body = SavedView(key: ValueKey('saved-${s.orderNo}'));
        break;
      case 'report':
        body = ReportView(key: ValueKey('report-${identityHashCode(s.report)}'));
        break;
      default:
        body = const ChatView(key: ValueKey('chat'));
    }
    return Column(children: [
      _StepBar(stage: s.stage),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: body,
        ),
      ),
    ]);
  }
}

class _StepBar extends StatelessWidget {
  final String stage;
  const _StepBar({required this.stage});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final labels = [s.t('s_describe'), s.t('s_review'), s.t('s_record'), s.t('s_payment'), s.t('s_report')];
    final now = {'describe': 0, 'review': 1, 'confirmed': 3, 'report': 4}[stage] ?? 0;
    return Container(
      color: C.bg,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(labels[now], style: T.display(s.ur, size: 17, color: C.indigo)),
          const Spacer(),
          Text(s.t('step_of', {'n': now + 1}), style: T.body(s.ur, size: 12.5, color: C.mute, w: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsetsDirectional.only(end: 4),
                decoration: BoxDecoration(
                  color: i < now ? C.leaf : (i == now ? C.madder : C.line),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'ai_view.dart';

/// A short "More" sheet: read-aloud, how Amana works, about. No keys, no server settings.
Future<void> showMoreSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _MoreSheet(),
  );
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(9))),
          ),
          const SizedBox(height: 16),
          Text(s.t('more'), style: T.display(ur, size: 22)),
          const SizedBox(height: 12),
          AmCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => s.setTts(!s.ttsOn),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(children: [
                    const Icon(Icons.volume_up_outlined, color: C.indigo2),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.t('sb_tts'), style: T.body(ur, size: 16, w: FontWeight.w600))),
                    Switch(value: s.ttsOn, onChanged: (v) => s.setTts(v)),
                  ]),
                ),
              ),
              const Divider(height: 1, color: C.line),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiViewScreen()));
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.hub_outlined, color: C.indigo2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.t('how_it_works'), style: T.body(ur, size: 16, w: FontWeight.w600)),
                        Text(s.t('how_sub'), style: T.body(ur, size: 13, color: C.mute)),
                      ]),
                    ),
                    Icon(ur ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: C.mute),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Text(s.t('about_text'), style: T.body(ur, size: 13.5, color: C.mute)),
          const SizedBox(height: 4),
          Text('Amana AI · v1.0', style: T.body(false, size: 12, color: C.mute)),
        ]),
      ),
    );
  }
}

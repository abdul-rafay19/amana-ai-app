import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/segmented.dart';
import 'records_screen.dart';
import 'safe_screen.dart';
import 'settings_sheet.dart';
import '../widgets/mark.dart';
import 'work_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppState? _s;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.read<AppState>();
    if (!identical(_s, s)) {
      _s?.removeListener(_onChange);
      _s = s;
      s.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    _s?.removeListener(_onChange);
    super.dispose();
  }

  /// Shows server/validation errors as a snackbar.
  void _onChange() {
    final s = _s;
    if (s == null || !mounted) return;
    final f = s.takeFlash();
    if (f == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: f.error ? C.madder : C.indigo,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Text(f.message,
          style: T.body(s.ur, size: 14.5, color: C.white, w: FontWeight.w600)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      backgroundColor: C.bg,
      body: Column(children: [
        _Header(),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: IndexedStack(
                index: s.tab,
                sizing: StackFit.expand,
                children: const [WorkScreen(), RecordsScreen(), SafeScreen()],
              ),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: const _NavBar(),
    );
  }
}

// ---------------------------------------------------------------- header
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        color: C.white,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
            child: Row(children: [
              const AmanaMark(size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.t('app_name'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: T.display(s.ur, size: 24)),
              ),
              Segmented(
                compact: true,
                labels: const ['EN', 'اردو'],
                index: s.ur ? 1 : 0,
                onChanged: (i) => s.setLang(i == 1 ? 'ur' : 'en'),
              ),
              if (s.hasPin)
                IconButton(
                  tooltip: s.t('lock_now_short'),
                  icon: const Icon(Icons.lock_outline_rounded, color: C.indigo),
                  onPressed: () => s.lockNow(),
                ),
              IconButton(
                tooltip: s.t('more'),
                icon: const Icon(Icons.more_vert_rounded, color: C.indigo),
                onPressed: () => showMoreSheet(context),
              ),
            ]),
          ),
        ),
      ),
      const AjrakStrip(height: 8),
    ]);
  }
}

// ---------------------------------------------------------------- bottom nav
class _NavBar extends StatelessWidget {
  const _NavBar();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = <(IconData, IconData, String)>[
      (Icons.forum_outlined, Icons.forum_rounded, s.t('nav_work')),
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, s.t('nav_records')),
      (Icons.shield_outlined, Icons.shield_rounded, s.t('nav_safe')),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: C.white,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => s.setTab(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: s.tab == i ? C.tint : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(s.tab == i ? items[i].$2 : items[i].$1,
                          size: 24, color: s.tab == i ? C.indigo : C.mute),
                      const SizedBox(height: 3),
                      Text(items[i].$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.body(s.ur,
                              size: 12.5,
                              w: s.tab == i ? FontWeight.w800 : FontWeight.w600,
                              color: s.tab == i ? C.indigo : C.mute,
                              height: 1.2)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

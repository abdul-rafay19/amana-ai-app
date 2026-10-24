import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/voice.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/chat_bits.dart';
import '../widgets/common.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final VoiceRecorder _voice = VoiceRecorder();
  bool _recording = false;
  bool _transcribing = false;
  bool _heard = false;
  int _lastCount = -1;
  bool _lastSending = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  Future<void> _send([String? override]) async {
    final s = context.read<AppState>();
    final txt = (override ?? _text.text).trim();
    if (txt.isEmpty || s.sending) return;
    if (override == null) _text.clear();
    setState(() => _heard = false);
    final ok = await s.sendChat(txt);
    if (!ok && override == null && mounted) _text.text = txt; // give the text back so nothing is lost
  }

  Future<void> _toggleMic() async {
    final s = context.read<AppState>();
    if (_recording) {
      setState(() {
        _recording = false;
        _transcribing = true;
      });
      String? path;
      try {
        path = await _voice.stop();
      } catch (_) {
        path = null;
      }
      String? heard;
      if (path != null) heard = await s.transcribe(path);
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (heard != null && heard.trim().isNotEmpty) {
        _text.text = heard.trim();
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
        setState(() => _heard = true);
        _focus.requestFocus();
      }
      return;
    }
    try {
      FocusScope.of(context).unfocus();
      final ok = await _voice.start();
      if (!ok) {
        s.flash(s.t('mic_denied'), error: true);
        return;
      }
      if (mounted) {
        setState(() {
          _recording = true;
          _heard = false;
        });
      }
    } catch (_) {
      s.flash(s.t('err_generic'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final kb = MediaQuery.of(context).viewInsets.bottom > 0;

    if (s.chat.length != _lastCount || s.sending != _lastSending) {
      _lastCount = s.chat.length;
      _lastSending = s.sending;
      _scrollDown();
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            children: [
              Bubble(text: s.t('greet'), mine: false),
              for (final m in s.chat) Bubble(text: m.s('text') ?? '', mine: m['role'] == 'user'),
              if (s.sending) const TypingBubble(),
              if (s.chat.isEmpty && !s.sending) _Examples(onPick: (t) => _send(t)),
            ],
          ),
        ),
        if (!kb) ...[
          _Ticket(),
          _Actions(),
        ],
        if (_recording || _transcribing || _heard)
          _StatusLine(recording: _recording, transcribing: _transcribing, heard: _heard),
        _Composer(
          controller: _text,
          focus: _focus,
          recording: _recording,
          transcribing: _transcribing,
          sending: s.sending,
          onMic: _toggleMic,
          onSend: _send,
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- examples (three small pills)
class _Examples extends StatelessWidget {
  final void Function(String) onPick;
  const _Examples({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = [
      ('English', s.t('sample_en')),
      ('Roman Urdu', s.t('sample_ro')),
      ('اردو', s.t('sample_ur')),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t('tip_try'), style: T.body(s.ur, size: 13.5, w: FontWeight.w700, color: C.mute)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final it in items)
            Material(
              color: C.white,
              shape: const StadiumBorder(side: BorderSide(color: C.line)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onPick(it.$2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.touch_app_outlined, size: 18, color: C.indigo2),
                      const SizedBox(width: 8),
                      Text(it.$1, style: T.body(hasUrdu(it.$1), size: 15, w: FontWeight.w700, color: C.indigo)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- order ticket (only what is filled)
class _Ticket extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.draft;
    final ur = s.ur;

    String? val(String key) {
      final v = d[key];
      if (v == null) return null;
      final n = v is num ? v : num.tryParse('$v');
      switch (key) {
        case 'rate_per_piece':
        case 'material_expenses':
          return fmtRs(n);
        case 'estimated_hours':
          return '${fmtNum(n)} ${s.t('hours')}';
        case 'deadline_days':
          return '${fmtNum(n)} ${s.t('days')}';
        case 'quantity':
          return fmtNum(n);
        default:
          return '$v';
      }
    }

    final fields = <(String, String)>[
      ('quantity', s.t('f_quantity')),
      ('rate_per_piece', s.t('f_rate')),
      ('material_expenses', s.t('f_materials')),
      ('estimated_hours', s.t('f_hours')),
      ('deadline_days', s.t('f_deadline')),
      ('payment_terms', s.t('f_terms')),
      ('item', s.t('f_item')),
    ];
    final filled = [for (final f in fields) if (d[f.$1] != null) f];
    if (filled.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        color: C.white,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s.t('so_far')}  ·  ${filled.length}/${fields.length}',
            style: T.body(ur, size: 12.5, w: FontWeight.w800, color: C.mute)),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final f in filled)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.leafBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${f.$2}: ', style: T.body(ur, size: 12.5, color: C.mute, w: FontWeight.w600)),
                      Text(val(f.$1) ?? '',
                          textDirection: dirOf(val(f.$1) ?? ''),
                          style: T.body(hasUrdu(val(f.$1) ?? ''), size: 13.5, w: FontWeight.w800)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- action buttons
class _Actions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final optionalAsk = s.asked != null && !const ['quantity', 'rate_per_piece'].contains(s.asked);
    if (!s.canCalc && !optionalAsk) return const SizedBox.shrink();
    return Container(
      color: C.white,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(children: [
        if (s.canCalc)
          AmButton(
            label: s.t('btn_numbers'),
            ur: ur,
            icon: Icons.calculate_rounded,
            busy: s.busy,
            onTap: () => s.evaluate(),
          ),
        if (optionalAsk)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => s.skipQuestion(),
              child: Text(s.t('btn_skip'), style: T.body(ur, size: 14, w: FontWeight.w700, color: C.indigo2)),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- status + composer
class _StatusLine extends StatelessWidget {
  final bool recording;
  final bool transcribing;
  final bool heard;
  const _StatusLine({required this.recording, required this.transcribing, required this.heard});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    String text;
    Color color;
    IconData icon;
    if (recording) {
      text = s.t('recording');
      color = C.madder;
      icon = Icons.fiber_manual_record_rounded;
    } else if (transcribing) {
      text = s.t('transcribing');
      color = C.indigo2;
      icon = Icons.graphic_eq_rounded;
    } else {
      text = s.t('heard');
      color = C.leaf;
      icon = Icons.hearing_rounded;
    }
    return Container(
      width: double.infinity,
      color: C.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: T.body(s.ur, size: 13.5, w: FontWeight.w700, color: color))),
      ]),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool recording;
  final bool transcribing;
  final bool sending;
  final VoidCallback onMic;
  final Future<void> Function([String?]) onSend;
  const _Composer({
    required this.controller,
    required this.focus,
    required this.recording,
    required this.transcribing,
    required this.sending,
    required this.onMic,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ur = s.ur;
    final canSend = controller.text.trim().isNotEmpty && !sending && !recording && !transcribing;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 8),
      decoration: const BoxDecoration(
        color: C.white,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Semantics(
          button: true,
          label: s.t('tap_mic'),
          child: MicButton(recording: recording, busy: transcribing, onTap: onMic, size: 52),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focus,
            minLines: 1,
            maxLines: 4,
            maxLength: 1000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: T.body(ur, size: 16.5),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: C.tint,
              hintText: s.t('type_ph'),
              hintStyle: T.body(ur, size: 14.5, color: C.mute),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: C.indigo2, width: 1.6)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: s.t('send'),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: canSend ? 1 : 0.4,
            child: Material(
              color: C.madder,
              shape: const CircleBorder(),
              child: InkResponse(
                customBorder: const CircleBorder(),
                onTap: canSend ? () => onSend() : null,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.arrow_upward_rounded, color: C.white, size: 26),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

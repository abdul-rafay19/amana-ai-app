import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records a short clip for the server to transcribe (the server holds the AI keys).
/// Prefers 16 kHz mono WAV; falls back to AAC (m4a) if WAV is not supported on this phone.
class VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();

  /// false = microphone permission was refused.
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final wavOk = await _rec.isEncoderSupported(AudioEncoder.wav);
    final cfg = RecordConfig(
      encoder: wavOk ? AudioEncoder.wav : AudioEncoder.aacLc,
      sampleRate: 16000,
      numChannels: 1,
    );
    final ext = wavOk ? 'wav' : 'm4a';
    final path = '${dir.path}/amana_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _rec.start(cfg, path: path);
    return true;
  }

  Future<String?> stop() => _rec.stop();

  Future<void> dispose() => _rec.dispose();
}

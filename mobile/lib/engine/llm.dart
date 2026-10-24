import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../app_config.dart';

// Optional build-time keys:  flutter build apk --dart-define=GROQ_API_KEY=...
// Keys can also be pasted in the app's Settings. With no key at all the app runs in offline rule-based mode.
const String _buildGemini = String.fromEnvironment('GEMINI_API_KEY');
const String _buildGroq = String.fromEnvironment('GROQ_API_KEY');
const String _buildNvidia = String.fromEnvironment('NVIDIA_API_KEY');
// Optional: your hosted AI proxy (see ai-proxy/). With it, NO provider key is inside the app.
// The proxy address and token live in lib/app_config.dart. A placeholder address counts as "not set".
String get _buildProxy => kAiProxyUrl.contains('YOUR-PROJECT') ? '' : kAiProxyUrl;
const String _buildProxyToken = kAiProxyToken;
const String _buildOrder = String.fromEnvironment('PROVIDER_ORDER', defaultValue: 'gemini,groq,nvidia');

class LLMUnavailable implements Exception {
  final String message;
  LLMUnavailable(this.message);
  @override
  String toString() => message;
}

class _Provider {
  final String base;
  final String model;
  const _Provider(this.base, this.model);
}

const Map<String, _Provider> _providers = {
  'gemini': _Provider('https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-flash-lite-latest'),
  'groq': _Provider('https://api.groq.com/openai/v1', 'openai/gpt-oss-120b'),
  'nvidia': _Provider('https://integrate.api.nvidia.com/v1', 'meta/llama-3.3-70b-instruct'),
};

/// One thin wrapper for Gemini, Groq and NVIDIA (all OpenAI-compatible). If one provider is
/// rate-limited or down, the next one is tried automatically. Runs directly on the phone.
class Llm {
  final http.Client client;
  Llm({http.Client? client}) : client = client ?? http.Client();

  /// Keys typed in Settings (override the build-time ones).
  final Map<String, String> keys = {};

  String? _key(String p) {
    final o = keys[p];
    if (o != null && o.trim().isNotEmpty) return o.trim();
    final b = p == 'gemini' ? _buildGemini : (p == 'groq' ? _buildGroq : _buildNvidia);
    return b.isEmpty ? null : b;
  }

  String modelFor(String p) => _providers[p]!.model;

  /// Address of the AI proxy (Settings overrides the build-time value).
  String? get proxyUrl {
    final o = keys['proxy']?.trim();
    var u = (o != null && o.isNotEmpty) ? o : _buildProxy;
    if (u.isEmpty) return null;
    if (!u.startsWith('http')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get _proxyHeaders => {
        if (_buildProxyToken.isNotEmpty) 'x-app-token': _buildProxyToken,
      };

  /// 'proxy' (if configured) comes first, then providers whose key is on this phone.
  List<String> available() => [
        if (proxyUrl != null) 'proxy',
        ..._buildOrder
            .split(',')
            .map((e) => e.trim())
            .where((p) => _providers.containsKey(p) && _key(p) != null),
      ];

  Map<String, dynamic> status() {
    final av = available();
    return {
      'mode': av.isNotEmpty ? 'ai' : 'offline',
      'providers': av,
      'voice': proxyUrl != null || _key('groq') != null || _key('gemini') != null,
    };
  }

  Future<Map<String, dynamic>?> _chatViaProxy(Map<String, dynamic> body, int timeout) async {
    final url = proxyUrl;
    if (url == null) return null;
    final sw = Stopwatch()..start();
    try {
      final r = await client
          .post(Uri.parse('$url/api/chat'),
              headers: {..._proxyHeaders, 'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode({
                'messages': body['messages'],
                if (body['tools'] != null) 'tools': body['tools'],
                if (body['response_format'] != null) 'response_format': body['response_format'],
                'temperature': body['temperature'],
                'max_tokens': body['max_tokens'],
              }))
          .timeout(Duration(seconds: timeout + 15)); // free hosts can need a few seconds to wake up
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final msg = Map<String, dynamic>.from((j['choices'] as List)[0]['message'] as Map);
      final meta = j['_amana'] is Map ? Map<String, dynamic>.from(j['_amana'] as Map) : <String, dynamic>{};
      return _normalize(msg, 'proxy:${meta['provider'] ?? '?'}', (meta['model'] ?? '').toString(), sw.elapsedMilliseconds);
    } catch (_) {
      return null; // proxy asleep or unreachable: fall through to local keys, then offline mode
    }
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> msg, String provider, String model, int ms) {
    final calls = <Map<String, dynamic>>[];
    final tcs = msg['tool_calls'];
    if (tcs is List) {
      for (final tc in tcs) {
        if (tc is! Map) continue;
        final fn = tc['function'] is Map ? Map<String, dynamic>.from(tc['function'] as Map) : <String, dynamic>{};
        dynamic args;
        try {
          args = jsonDecode((fn['arguments'] ?? '{}').toString());
        } catch (_) {
          args = <String, dynamic>{};
        }
        calls.add({
          'id': (tc['id'] ?? 'call_${Random().nextInt(1 << 31).toRadixString(16)}').toString(),
          'name': fn['name'],
          'arguments': args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
        });
      }
    }
    return {
      'content': (msg['content'] ?? '').toString().trim(),
      'tool_calls': calls,
      'provider': provider,
      'model': model,
      'ms': ms,
    };
  }

  /// Rebuilds an OpenAI-style assistant message so the tool loop can continue.
  Map<String, dynamic> assistantMessage(Map<String, dynamic> resp) {
    final m = <String, dynamic>{'role': 'assistant', 'content': resp['content'] ?? ''};
    final calls = resp['tool_calls'] as List;
    if (calls.isNotEmpty) {
      m['tool_calls'] = [
        for (final c in calls)
          {
            'id': c['id'],
            'type': 'function',
            'function': {'name': c['name'], 'arguments': jsonEncode(c['arguments'])},
          }
      ];
    }
    return m;
  }

  Future<Map<String, dynamic>> chat(List<Map<String, dynamic>> messages,
      {List<Map<String, dynamic>>? tools,
      double temperature = 0.2,
      int maxTokens = 900,
      bool jsonMode = false,
      int timeout = 30}) async {
    final provs = available();
    if (provs.isEmpty) throw LLMUnavailable('No AI configured');
    String? lastErr;
    if (provs.first == 'proxy') {
      final viaProxy = await _chatViaProxy({
        'messages': messages,
        'tools': tools,
        'temperature': temperature,
        'max_tokens': maxTokens,
        if (jsonMode && tools == null) 'response_format': {'type': 'json_object'},
      }, timeout);
      if (viaProxy != null) return viaProxy;
      lastErr = 'proxy unreachable';
    }
    for (final p in provs.where(_providers.containsKey)) {
      final cfg = _providers[p]!;
      final body = <String, dynamic>{
        'model': cfg.model,
        'messages': messages,
        'temperature': temperature,
        'max_tokens': maxTokens,
      };
      if (tools != null) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }
      if (jsonMode && tools == null) body['response_format'] = {'type': 'json_object'};
      for (var attempt = 0; attempt < 2; attempt++) {
        final sw = Stopwatch()..start();
        try {
          final r = await client
              .post(Uri.parse('${cfg.base}/chat/completions'),
                  headers: {
                    'Authorization': 'Bearer ${_key(p)}',
                    'Content-Type': 'application/json; charset=utf-8',
                  },
                  body: jsonEncode(body))
              .timeout(Duration(seconds: timeout));
          if ([429, 500, 502, 503, 504].contains(r.statusCode)) {
            lastErr = '$p: HTTP ${r.statusCode}';
            await Future<void>.delayed(Duration(milliseconds: 1200 * (attempt + 1)));
            continue;
          }
          if (r.statusCode < 200 || r.statusCode >= 300) {
            lastErr = '$p: HTTP ${r.statusCode}';
            break;
          }
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          final msg = Map<String, dynamic>.from((j['choices'] as List)[0]['message'] as Map);
          return _normalize(msg, p, cfg.model, sw.elapsedMilliseconds);
        } catch (e) {
          lastErr = '$p: ${e.runtimeType}';
          break;
        }
      }
    }
    throw LLMUnavailable(lastErr ?? 'all providers failed');
  }

  Future<String> _geminiStt(Uint8List bytes, String mime) async {
    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'inlineData': {'mimeType': mime, 'data': base64Encode(bytes)}},
            {'text': 'Transcribe this audio exactly. Write Urdu in Urdu script. Output only the transcript.'},
          ]
        }
      ],
      'generationConfig': {'temperature': 0},
    };
    final r = await client
        .post(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/${modelFor('gemini')}:generateContent'),
            headers: {'x-goog-api-key': _key('gemini')!, 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 45));
    if (r.statusCode < 200 || r.statusCode >= 300) throw LLMUnavailable('gemini: HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final parts = (((j['candidates'] as List)[0] as Map)['content'] as Map)['parts'] as List;
    return parts.map((p) => (p as Map)['text'] ?? '').join().trim();
  }

  /// Speech to text: Whisper on Groq first, Gemini audio as the fallback.
  Future<String> transcribe(Uint8List bytes, String filename, {String language = 'ur', String mime = 'audio/wav'}) async {
    final errors = <String>[];
    final px = proxyUrl;
    if (px != null) {
      try {
        final r = await client
            .post(Uri.parse('$px/api/stt'),
                headers: {..._proxyHeaders, 'Content-Type': mime, 'x-filename': filename, 'x-language': language},
                body: bytes)
            .timeout(const Duration(seconds: 60));
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          return (j['text'] ?? '').toString().trim();
        }
        errors.add('proxy: HTTP ${r.statusCode}');
      } catch (e) {
        errors.add('proxy: ${e.runtimeType}');
      }
    }
    if (_key('groq') != null) {
      try {
        final req = http.MultipartRequest('POST', Uri.parse('${_providers['groq']!.base}/audio/transcriptions'));
        req.headers['Authorization'] = 'Bearer ${_key('groq')}';
        req.fields.addAll({
          'model': 'whisper-large-v3',
          if (language == 'ur' || language == 'en') 'language': language,
          if (language != 'ur') 'prompt': 'Pakistani speaker. Urdu, Roman Urdu or English. Piecework order, rate per piece, rupees.',
          'response_format': 'json',
          'temperature': '0',
        });
        req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
        final streamed = await client.send(req).timeout(const Duration(seconds: 45));
        final r = await http.Response.fromStream(streamed);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          return (j['text'] ?? '').toString().trim();
        }
        errors.add('groq: HTTP ${r.statusCode}');
      } catch (e) {
        errors.add('groq: ${e.runtimeType}');
      }
    }
    if (_key('gemini') != null) {
      try {
        return await _geminiStt(bytes, mime);
      } catch (e) {
        errors.add('gemini: ${e.runtimeType}');
      }
    }
    throw LLMUnavailable(errors.isEmpty ? 'Voice needs a Groq or Gemini key' : errors.join('; '));
  }
}

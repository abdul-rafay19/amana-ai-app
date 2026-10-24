// Run with:  flutter test
// 1) golden tests: the Dart engine must give the SAME answers as the tested Python code (test/golden.json)
// 2) journey tests: the whole worker flow through LocalApi, fully offline, no server.
import 'dart:convert';
import 'dart:io';

import 'package:amana_app/engine/calc.dart' as calc;
import 'package:amana_app/engine/offline.dart' as off;
import 'package:amana_app/services/api.dart';
import 'package:amana_app/services/local_api.dart';
import 'package:flutter_test/flutter_test.dart';

void same(dynamic actual, dynamic expected, [String path = '']) {
  if (expected is num && actual is num) {
    expect((actual - expected).abs() < 1e-9, true, reason: '$path: got $actual, expected $expected');
  } else if (expected is Map) {
    expect(actual, isA<Map>(), reason: path);
    final a = actual as Map;
    expect(a.keys.toSet(), expected.keys.toSet(), reason: '$path keys');
    for (final k in expected.keys) {
      same(a[k], expected[k], '$path.$k');
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: path);
    final a = actual as List;
    expect(a.length, expected.length, reason: '$path length');
    for (var i = 0; i < expected.length; i++) {
      same(a[i], expected[i], '$path[$i]');
    }
  } else {
    expect(actual, expected, reason: path);
  }
}

Future<LocalApi> fresh() async {
  final api = LocalApi();
  await api.init(useDocs: false); // in-memory store
  return api;
}

Future<Map> say(LocalApi api, String text) async => (await api.post('/chat', {'text': text})) as Map;

Future<Map> confirmedOrder(LocalApi api) async {
  await say(api, 'Mujhe 30 frock ka order mila hai, 250 rupay per piece, 5 din mein dena hai.');
  await api.post('/deal/evaluate', {'lang': 'en'});
  return (await api.post('/record/confirm') as Map)['record'] as Map;
}

void main() {
  final g = jsonDecode(File('test/golden.json').readAsStringSync()) as Map<String, dynamic>;

  group('golden: same answers as Python', () {
    test('calculate_deal', () {
      for (final c in g['deal'] as List) {
        final i = c['in'] as List;
        same(calc.calculateDeal(i[0], i[1], i[2], i[3]), c['out'], 'deal $i');
      }
    });
    test('required_rate_for_target', () {
      for (final c in g['req'] as List) {
        final i = c['in'] as List;
        same(calc.requiredRateForTarget(i[0], i[1], i[2], i[3], i[4]), c['out'], 'req $i');
      }
    });
    test('compare_payment', () {
      for (final c in g['cmp'] as List) {
        final i = c['in'] as List;
        same(calc.comparePayment(i[0], i[1], advancePaid: i[2], agreedDeductions: i[3], isPartial: i[4] as bool), c['out'],
            'cmp $i');
      }
    });
    test('analyze_risks', () {
      for (final c in g['risks'] as List) {
        final got = calc.analyzeRisks(Map<String, dynamic>.from(c['order'] as Map), Map<String, dynamic>.from(c['calc'] as Map),
            c['min_hourly'] as num?);
        same(got, c['out'], 'risks');
      }
    });
    test('offline extraction', () {
      for (final c in g['extract'] as List) {
        same(off.extractOffline(c['text'] as String, c['asked'] as String?), c['out'], c['text'] as String);
      }
    });
    test('language detection and normalising', () {
      for (final c in g['lang'] as List) {
        expect(off.detectLang(c['text'] as String), c['out'], reason: c['text'] as String);
      }
      for (final c in g['normalize'] as List) {
        expect(off.normalize(c['text'] as String), c['out'], reason: c['text'] as String);
      }
    });
  });

  group('worker journey, fully on the phone', () {
    test('chat extracts details and numbers come from code', () async {
      final api = await fresh();
      final j = await say(api, 'Mujhe 30 frock ka order mila hai, 250 rupay per piece, 5 din mein dena hai.');
      expect(j['draft']['quantity'], 30);
      expect(j['draft']['rate_per_piece'], 250);
      expect(j['can_calc'], true);
      final ev = await api.post('/deal/evaluate', {'lang': 'en'}) as Map;
      expect(ev['calc']['expected_total'], 7500);
      expect((ev['explain'] as String).isNotEmpty, true);
    });

    test('nothing is saved without Confirm', () async {
      final api = await fresh();
      await say(api, '30 frock, 250 rupay per piece');
      await api.post('/deal/evaluate', {'lang': 'en'});
      expect(((await api.get('/records')) as Map)['orders'], isEmpty);
      await api.post('/record/confirm');
      expect((((await api.get('/records')) as Map)['orders'] as List).length, 1);
    });

    test('evaluate needs required fields; confirm needs review stage', () async {
      final api = await fresh();
      expect(() => api.post('/deal/evaluate', {'lang': 'en'}), throwsA(isA<ApiException>()));
      expect(() => api.post('/record/confirm'), throwsA(isA<ApiException>()));
    });

    test('counteroffer needs hours, then suggests a higher rate', () async {
      final api = await fresh();
      await say(api, '30 frock, 250 rupay per piece');
      await say(api, '1200 ka material lagega');
      await say(api, '20 hours lagenge');
      await api.post('/deal/evaluate', {'lang': 'en'});
      final co = (await api.post('/deal/counter', {'target_hourly': 500, 'lang': 'en'}) as Map)['counter'] as Map;
      expect(co['suggested_rate'] > co['current_rate'], true);
      expect((co['message'] as String).isNotEmpty, true);
    });

    test('short payment, message approval gives a link, never sends', () async {
      final api = await fresh();
      final rec = await confirmedOrder(api);
      final r = await api.multipart('/payment/check', {'order_no': rec['order_no'], 'received': '6500', 'lang': 'en'}) as Map;
      expect(r['blocked'], false);
      expect(r['report']['comparison']['status'], 'short');
      expect(r['report']['comparison']['unexplained'], 1000);
      final a = await api.post('/message/approve', {'text': '${r['msg_text']} Thanks.'}) as Map;
      expect((a['whatsapp_url'] as String).startsWith('https://wa.me/?text='), true);
      final recs = await api.get('/records') as Map;
      expect(recs['summary']['open'], 1000);
    });

    test('advance and agreed deduction explain the gap', () async {
      final api = await fresh();
      final rec = await confirmedOrder(api);
      final r = await api.multipart('/payment/check', {
        'order_no': rec['order_no'],
        'received': '6500',
        'advance_paid': '500',
        'agreed_deductions': '500',
      }) as Map;
      expect(r['report']['comparison']['status'], 'explained');
    });

    test('negative amount and unknown order are rejected', () async {
      final api = await fresh();
      final rec = await confirmedOrder(api);
      expect(() => api.multipart('/payment/check', {'order_no': rec['order_no'], 'received': '-5'}),
          throwsA(isA<ApiException>()));
      expect(() => api.multipart('/payment/check', {'order_no': 'AM-0000-999', 'received': '5'}),
          throwsA(isA<ApiException>()));
    });

    test('tampering is caught and blocks the payment check', () async {
      final api = await fresh();
      final rec = await confirmedOrder(api);
      final no = rec['order_no'] as String;
      final t = await api.post('/demo/tamper', {'order_no': no}) as Map;
      expect(t['changed_field'], 'rate_per_piece');
      final o = ((await api.get('/records')) as Map)['orders'][0] as Map;
      expect(o['integrity']['ok'], false);
      expect(o['integrity']['changed_fields'], ['rate_per_piece']);
      final v = await api.post('/records/verify') as Map;
      expect(v['ok'], false);
      final b = await api.multipart('/payment/check', {'order_no': no, 'received': '6500'}) as Map;
      expect(b['blocked'], true);
      expect((((await api.get('/records')) as Map)['orders'][0]['payments'] as List), isEmpty);
      await api.post('/demo/restore', {'order_no': no});
      expect(((await api.post('/records/verify')) as Map)['ok'], true);
    });

    test('sample data loads once; wipe clears everything', () async {
      final api = await fresh();
      await api.post('/demo/sample');
      expect(() => api.post('/demo/sample'), throwsA(isA<ApiException>()));
      expect(((await api.get('/records')) as Map)['summary']['orders'], 1);
      await api.delete('/data');
      expect(((await api.get('/records')) as Map)['orders'], isEmpty);
    });

    test('new order resets the chat', () async {
      final api = await fresh();
      await confirmedOrder(api);
      final s = await api.post('/chat/reset') as Map;
      expect(s['stage'], 'describe');
      expect(s['draft'], isEmpty);
      expect(s['chat'], isEmpty);
    });

    test('safe mode: lock blocks data, wrong PIN counts, right PIN unlocks, off needs PIN', () async {
      final api = await fresh();
      expect(() => api.post('/safe/pin', {'pin': '12ab'}), throwsA(isA<ApiException>()));
      expect(((await api.post('/safe/pin', {'pin': '1234'})) as Map)['has_pin'], true);
      expect(await api.get('/state'), isA<Map>());
      expect(((await api.post('/safe/lock')) as Map)['locked'], true);
      await expectLater(api.get('/state'), throwsA(isA<LockedException>()));
      await expectLater(api.post('/chat', {'text': 'hi'}), throwsA(isA<LockedException>()));
      final bad = await api.post('/safe/verify', {'pin': '0000'}) as Map;
      expect(bad['ok'], false);
      expect(bad['attempts_left'], 4);
      expect(((await api.post('/safe/verify', {'pin': '1234'})) as Map)['ok'], true);
      expect(await api.get('/state'), isA<Map>());
      await expectLater(api.post('/safe/off', {'pin': '0000'}), throwsA(isA<ApiException>()));
      expect(((await api.post('/safe/off', {'pin': '1234'})) as Map)['has_pin'], false);
    });

    test('five wrong PINs trigger a lockout', () async {
      final api = await fresh();
      await api.post('/safe/pin', {'pin': '1234'});
      await api.post('/safe/lock');
      for (var i = 0; i < 5; i++) {
        await api.post('/safe/verify', {'pin': '9999'});
      }
      await expectLater(api.post('/safe/verify', {'pin': '1234'}), throwsA(isA<ApiException>()));
    });

    test('data survives in the hash chain: records link to each other', () async {
      final api = await fresh();
      await confirmedOrder(api);
      await api.post('/chat/reset');
      await confirmedOrder(api);
      final r = await api.get('/records') as Map;
      final orders = r['orders'] as List;
      expect(orders.length, 2);
      expect(orders[0]['prev_hash'], orders[1]['hash']); // newest first; it points to the older one
      expect(((await api.post('/records/verify')) as Map)['ok'], true);
    });
  });
}

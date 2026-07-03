// ignore_for_file: avoid_print
// Dev end-to-end: glom cookies for <url> from <browser>, POST to the backend
// with them, and report the resulting title/error. Never prints cookie values.
//   dart run tool/test_download.dart <url> [chrome|firefox] [backendUrl]
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vget/cookies.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : '';
  final browser = args.length > 1 ? args[1] : 'chrome';
  final backend = args.length > 2 ? args[2] : 'http://localhost:8077';
  if (url.isEmpty) {
    print('usage: dart run tool/test_download.dart <url> [browser] [backend]');
    return;
  }

  final cookies = await extractCookies(browser: browser, url: url);
  final count = cookies == null
      ? 0
      : cookies.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).length;
  print('cookies: $count line(s) from $browser');

  final create = await http.post(Uri.parse('$backend/jobs'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'url': url, if (cookies != null) 'cookies': cookies}));
  if (create.statusCode != 200) {
    print('create failed: ${create.statusCode} ${create.body}');
    return;
  }
  final jobId = jsonDecode(create.body)['jobId'];
  print('jobId=$jobId');

  for (var i = 0; i < 90; i++) {
    await Future.delayed(const Duration(seconds: 1));
    final s = await http.get(Uri.parse('$backend/jobs/$jobId'));
    final j = jsonDecode(s.body);
    if (j['status'] == 'finished') {
      print('FINISHED: ${j['title']} -> ${j['filename']}');
      return;
    }
    if (j['status'] == 'error') {
      print('ERROR: ${j['error']}');
      return;
    }
  }
  print('timeout');
}

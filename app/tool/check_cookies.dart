// ignore_for_file: avoid_print
// Dev verification: extract cookies for a URL from a browser and print only
// the domain + cookie NAME (never values). Usage:
//   dart run tool/check_cookies.dart <url> <chrome|firefox>
import 'package:vget/cookies.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty
      ? args[0]
      : 'https://www.instagram.com/reel/DYm78k_s0rh/';
  final browser = args.length > 1 ? args[1] : 'chrome';

  final txt = await extractCookies(browser: browser, url: url);
  if (txt == null) {
    print('RESULT: null (no cookies / unsupported / error)');
    return;
  }
  final lines =
      txt.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
  print('RESULT: ${lines.length} cookies from $browser for $url');
  for (final l in lines) {
    final p = l.split('\t');
    if (p.length >= 6) print('  ${p[0]}\t${p[5]}'); // domain + name only
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:sqlite3/sqlite3.dart';

/// Chromium-family browsers: id -> [support-dir relative path, Keychain service].
/// They share the same cookie DB layout + AES-CBC encryption scheme; only the
/// on-disk path and the Keychain item name differ.
const _chromium = <String, List<String>>{
  'chrome': ['Google/Chrome', 'Chrome Safe Storage'],
  'brave': ['BraveSoftware/Brave-Browser', 'Brave Safe Storage'],
  'edge': ['Microsoft Edge', 'Microsoft Edge Safe Storage'],
};

/// Browsers probed, in order, for 'auto' mode.
const _autoOrder = <String>['chrome', 'brave', 'edge', 'firefox'];

/// Extract cookies for [url]'s registrable domain from [browser]
/// ('auto' | 'chrome' | 'brave' | 'edge' | 'firefox') and return them as a
/// Netscape cookies.txt string, or null if none found. Best-effort: returns
/// null on any error. In 'auto' mode, the first browser with cookies wins.
Future<String?> extractCookies({
  required String browser,
  required String url,
}) async {
  try {
    final host = Uri.parse(url).host.toLowerCase();
    if (host.isEmpty) return null;
    final domain = _registrableDomain(host);

    if (browser == 'auto') {
      for (final b in _autoOrder) {
        final c = await _extractOne(b, domain);
        if (c.isNotEmpty) return _toNetscape(c);
      }
      return null;
    }
    final c = await _extractOne(browser, domain);
    return c.isEmpty ? null : _toNetscape(c);
  } catch (_) {
    return null;
  }
}

Future<List<_Cookie>> _extractOne(String browser, String domain) async {
  if (browser == 'firefox') return _firefoxCookies(domain);
  final spec = _chromium[browser];
  final home = Platform.environment['HOME'];
  if (spec == null || home == null) return [];
  return _chromiumCookies(
      '$home/Library/Application Support/${spec[0]}', spec[1], domain);
}

class _Cookie {
  final String host, name, value, path;
  final int expires; // unix seconds, 0 = session
  final bool secure;
  _Cookie(this.host, this.name, this.value, this.path, this.expires,
      this.secure);
}

String _registrableDomain(String host) {
  final parts = host.split('.');
  if (parts.length <= 2) return host;
  return parts.sublist(parts.length - 2).join('.');
}

bool _domainMatches(String cookieHost, String domain) {
  final h = cookieHost.startsWith('.') ? cookieHost.substring(1) : cookieHost;
  return h == domain || h.endsWith('.$domain');
}

String _toNetscape(List<_Cookie> cookies) {
  final b = StringBuffer('# Netscape HTTP Cookie File\n');
  for (final c in cookies) {
    if (c.name.isEmpty) continue;
    b.writeln([
      c.host,
      c.host.startsWith('.') ? 'TRUE' : 'FALSE',
      c.path.isEmpty ? '/' : c.path,
      c.secure ? 'TRUE' : 'FALSE',
      c.expires.toString(),
      c.name,
      c.value,
    ].join('\t'));
  }
  return b.toString();
}

/// Copy a (possibly locked, WAL-mode) DB plus its sidecars to a temp file so we
/// can read it while the browser is running. Returns the temp DB path.
String _copyDb(String path) {
  final tmpDir = Directory.systemTemp.createTempSync('vget_ck');
  final dst = '${tmpDir.path}/db';
  File(path).copySync(dst);
  for (final ext in ['-wal', '-shm']) {
    final f = File('$path$ext');
    if (f.existsSync()) f.copySync('$dst$ext');
  }
  return dst;
}

void _cleanup(String dbPath) {
  try {
    File(dbPath).parent.deleteSync(recursive: true);
  } catch (_) {}
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

// --- Chromium (Chrome / Brave / Edge) -------------------------------------

Future<List<_Cookie>> _chromiumCookies(
    String base, String keychainService, String domain) async {
  // Find the cookie DB first; if the browser isn't installed we return early
  // WITHOUT touching the Keychain (so 'auto' won't prompt for absent browsers).
  var dbPath = '';
  for (final profile in ['Default', 'Profile 1', 'Profile 2', 'Profile 3']) {
    for (final rel in ['Network/Cookies', 'Cookies']) {
      final p = '$base/$profile/$rel';
      if (File(p).existsSync()) {
        dbPath = p;
        break;
      }
    }
    if (dbPath.isNotEmpty) break;
  }
  if (dbPath.isEmpty) return [];

  final key = await _chromiumKey(keychainService);
  if (key == null) return [];

  final tmp = _copyDb(dbPath);
  final db = sqlite3.open(tmp);
  final out = <_Cookie>[];
  try {
    // Filter to the domain in SQL: reading the whole table can hit a cookie
    // from another site whose text isn't valid UTF-8 (the sqlite3 package
    // throws on decode). hex(encrypted_value) avoids blob/text ambiguity.
    final rows = db.select(
        'SELECT host_key, name, value, hex(encrypted_value) AS enc_hex, path, '
        'expires_utc, is_secure FROM cookies WHERE host_key LIKE ?',
        ['%$domain%']);
    for (final r in rows) {
      final hostKey = r['host_key'] as String;
      if (!_domainMatches(hostKey, domain)) continue;

      var value = (r['value'] as String?) ?? '';
      final encHex = r['enc_hex'] as String?;
      if (value.isEmpty && encHex != null && encHex.isNotEmpty) {
        final dec = _decryptChromium(_hexToBytes(encHex), key);
        if (dec == null) continue;
        value = dec;
      }

      final expUtc = (r['expires_utc'] as int?) ?? 0;
      final expUnix = expUtc == 0 ? 0 : (expUtc ~/ 1000000) - 11644473600;
      out.add(_Cookie(
        hostKey,
        r['name'] as String,
        value,
        (r['path'] as String?) ?? '/',
        expUnix < 0 ? 0 : expUnix,
        ((r['is_secure'] as int?) ?? 0) == 1,
      ));
    }
  } finally {
    db.dispose();
    _cleanup(tmp);
  }
  return out;
}

/// Derive a Chromium browser's AES key from its "Safe Storage" password in the
/// macOS Keychain (PBKDF2-HMAC-SHA1, salt "saltysalt", 1003 iters, 16 bytes).
Future<Uint8List?> _chromiumKey(String service) async {
  final res = await Process.run(
      '/usr/bin/security', ['find-generic-password', '-w', '-s', service]);
  if (res.exitCode != 0) return null;
  final password = (res.stdout as String).trim();
  if (password.isEmpty) return null;

  final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
    ..init(Pbkdf2Parameters(
        Uint8List.fromList(utf8.encode('saltysalt')), 1003, 16));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

String? _decryptChromium(Uint8List enc, Uint8List key) {
  if (enc.length <= 3) return null;
  final data = enc.sublist(3); // strip "v10"/"v11" prefix
  if (data.isEmpty || data.length % 16 != 0) return null;

  final iv = Uint8List(16)..fillRange(0, 16, 0x20); // 16 spaces
  final cbc = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), iv));
  final out = Uint8List(data.length);
  for (var off = 0; off < data.length; off += 16) {
    cbc.processBlock(data, off, out, off);
  }

  final pad = out.last; // PKCS7
  if (pad < 1 || pad > 16 || pad > out.length) return null;
  final plain = out.sublist(0, out.length - pad);

  try {
    return utf8.decode(plain);
  } catch (_) {
    // Newer Chromium prepends a 32-byte SHA256 domain hash before the value.
    if (plain.length > 32) {
      try {
        return utf8.decode(plain.sublist(32));
      } catch (_) {}
    }
    return null;
  }
}

// --- Firefox --------------------------------------------------------------

List<_Cookie> _firefoxCookies(String domain) {
  final home = Platform.environment['HOME'];
  if (home == null) return [];
  final base =
      Directory('$home/Library/Application Support/Firefox/Profiles');
  if (!base.existsSync()) return [];

  final profiles = base.listSync().whereType<Directory>().toList();
  Directory? chosen;
  for (final p in profiles) {
    if (p.path.endsWith('.default-release') &&
        File('${p.path}/cookies.sqlite').existsSync()) {
      chosen = p;
      break;
    }
  }
  chosen ??= profiles.cast<Directory?>().firstWhere(
        (p) => File('${p!.path}/cookies.sqlite').existsSync(),
        orElse: () => null,
      );
  if (chosen == null) return [];

  final dbPath = '${chosen.path}/cookies.sqlite';
  if (!File(dbPath).existsSync()) return [];

  final tmp = _copyDb(dbPath);
  final db = sqlite3.open(tmp);
  final out = <_Cookie>[];
  try {
    final rows = db.select(
        'SELECT host, name, value, path, expiry, isSecure FROM moz_cookies '
        'WHERE host LIKE ?',
        ['%$domain%']);
    for (final r in rows) {
      final host = r['host'] as String;
      if (!_domainMatches(host, domain)) continue;
      out.add(_Cookie(
        host,
        r['name'] as String,
        (r['value'] as String?) ?? '',
        (r['path'] as String?) ?? '/',
        (r['expiry'] as int?) ?? 0,
        ((r['isSecure'] as int?) ?? 0) == 1,
      ));
    }
  } finally {
    db.dispose();
    _cleanup(tmp);
  }
  return out;
}

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'cookies.dart';
import 'saver.dart';

void main() => runApp(const VGetApp());

/// Default backend URL. Override in the UI (Settings) at runtime.
const _defaultBackend = 'http://localhost:8077';
const _prefBackend = 'backendUrl';
const _prefDownloadDir = 'downloadDir';
const _prefCookieBrowser = 'cookieBrowser';

/// Browsers we can glom cookies from for authenticated downloads (desktop).
const _cookieBrowsers = <String>['none', 'chrome', 'firefox'];
const _cookieBrowserLabels = <String, String>{
  'none': 'None (public only)',
  'chrome': 'Chrome',
  'firefox': 'Firefox',
};

class VGetApp extends StatelessWidget {
  const VGetApp({super.key});

  // One Dark (Atom) palette
  static const _bg = Color(0xFF282C34);
  static const _bgDark = Color(0xFF21252B);
  static const _fg = Color(0xFFABB2BF);
  static const _blue = Color(0xFF61AFEF);
  static const _purple = Color(0xFFC678DD);
  static const _green = Color(0xFF98C379);
  static const _red = Color(0xFFE06C75);
  static const _grey = Color(0xFF5C6370);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _blue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _blue,
      onPrimary: _bg,
      secondary: _purple,
      onSecondary: _bg,
      surface: _bg,
      onSurface: _fg,
      error: _red,
      onError: _bg,
      surfaceContainerHighest: _bgDark,
      secondaryContainer: const Color(0xFF2E3A2E), // success card (green-tinted)
      onSecondaryContainer: _green,
      errorContainer: const Color(0xFF3A2D30), // error card (red-tinted)
      onErrorContainer: _red,
      outline: _grey,
    );
    return MaterialApp(
      title: 'VGet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _bgDark,
          foregroundColor: _fg,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlCtrl = TextEditingController();

  String _backendUrl = _defaultBackend;
  String? _downloadDir; // null => OS Downloads folder
  String _cookieBrowser = 'none'; // glom cookies from this browser
  late ApiClient _api = ApiClient(_backendUrl);

  Timer? _poll;
  JobStatus? _job;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backendUrl = prefs.getString(_prefBackend) ?? _defaultBackend;
      _downloadDir = prefs.getString(_prefDownloadDir);
      _cookieBrowser = prefs.getString(_prefCookieBrowser) ?? 'none';
      _api = ApiClient(_backendUrl);
    });
  }

  Future<void> _saveSettings(
      String backendUrl, String? downloadDir, String cookieBrowser) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBackend, backendUrl);
    await prefs.setString(_prefCookieBrowser, cookieBrowser);
    if (downloadDir == null || downloadDir.isEmpty) {
      await prefs.remove(_prefDownloadDir);
    } else {
      await prefs.setString(_prefDownloadDir, downloadDir);
    }
    setState(() {
      _backendUrl = backendUrl;
      _downloadDir = (downloadDir == null || downloadDir.isEmpty)
          ? null
          : downloadDir;
      _cookieBrowser = cookieBrowser;
      _api = ApiClient(_backendUrl);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    _poll?.cancel();
    setState(() {
      _busy = true;
      _job = null;
      _message = null;
      _messageIsError = false;
    });

    try {
      String? cookies;
      if (!kIsWeb && _cookieBrowser != 'none') {
        cookies = await extractCookies(browser: _cookieBrowser, url: url);
      }
      final id = await _api.createJob(url, cookies: cookies);
      _poll = Timer.periodic(const Duration(milliseconds: 800), (_) async {
        try {
          final job = await _api.getJob(id);
          setState(() => _job = job);
          if (job.isTerminal) {
            _poll?.cancel();
            if (job.isFinished) {
              await _onFinished(job);
            } else {
              setState(() {
                _busy = false;
                _message = _friendlyError(job.error);
                _messageIsError = true;
              });
            }
          }
        } catch (e) {
          _poll?.cancel();
          setState(() {
            _busy = false;
            _message = 'Error: $e';
            _messageIsError = true;
          });
        }
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _message = 'Error: $e';
        _messageIsError = true;
      });
    }
  }

  /// Turn a raw yt-dlp error into a hint when it looks like the content needed
  /// authentication but no cookie source was selected.
  String _friendlyError(String? err) {
    final e = err ?? 'download failed';
    final l = e.toLowerCase();
    final looksAuth = l.contains('empty media response') ||
        l.contains('login required') ||
        l.contains('log in') ||
        l.contains('cookies') ||
        l.contains('private') ||
        l.contains('rate-limit');
    if (looksAuth && (kIsWeb || _cookieBrowser == 'none')) {
      return 'This looks like private or login-required content. Open Settings '
          "(⚙) and set “Use cookies from” to the browser you're logged in with "
          '(e.g. Chrome), then try again.';
    }
    return 'Error: $e';
  }

  Future<void> _onFinished(JobStatus job) async {
    try {
      final where = await saveResult(_api, job, downloadDir: _downloadDir);
      setState(() {
        _busy = false;
        _message = kIsWeb ? where : 'Saved to: $where';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _message = 'Saved on server, but local save failed: $e';
        _messageIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final progress = (job?.progress ?? 0) / 100.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VGet'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _busy ? null : _openSettings,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Paste a link, get the media',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlCtrl,
                  enabled: !_busy,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Media URL',
                    hintText: 'https://...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  onSubmitted: (_) => _busy ? null : _start(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _start,
                  icon: const Icon(Icons.download),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_busy ? 'Working…' : 'Download'),
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Saving to: ${_downloadDir ?? 'Downloads folder'}'
                    '   •   Cookies: ${_cookieBrowserLabels[_cookieBrowser]}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                if (_busy && job != null) ...[
                  LinearProgressIndicator(
                    value: (job.status == 'downloading' && progress > 0)
                        ? progress
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(_statusLine(job),
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: _messageIsError
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(_messageIsError
                              ? Icons.error_outline
                              : Icons.check_circle_outline),
                          const SizedBox(width: 8),
                          Expanded(child: SelectableText(_message!)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLine(JobStatus job) {
    switch (job.status) {
      case 'queued':
        return 'Queued…';
      case 'downloading':
        return 'Downloading ${job.progress.toStringAsFixed(0)}%'
            '${job.title != null ? ' — ${job.title}' : ''}';
      case 'processing':
        return 'Processing${job.title != null ? ' — ${job.title}' : ''}…';
      case 'finished':
        return 'Finished${job.title != null ? ' — ${job.title}' : ''}';
      case 'error':
        return 'Failed';
      default:
        return job.status;
    }
  }

  Future<void> _openSettings() async {
    final result =
        await showDialog<({String backend, String? dir, String cookieBrowser})>(
      context: context,
      builder: (ctx) => _SettingsDialog(
        backendUrl: _backendUrl,
        downloadDir: _downloadDir,
        cookieBrowser: _cookieBrowser,
      ),
    );
    if (result != null) {
      await _saveSettings(result.backend, result.dir, result.cookieBrowser);
    }
  }
}

/// Settings: backend URL + (desktop) download folder picker.
class _SettingsDialog extends StatefulWidget {
  final String backendUrl;
  final String? downloadDir;
  final String cookieBrowser;
  const _SettingsDialog({
    required this.backendUrl,
    this.downloadDir,
    required this.cookieBrowser,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _backendCtrl =
      TextEditingController(text: widget.backendUrl);
  String? _dir;
  late String _cookieBrowser;

  @override
  void initState() {
    super.initState();
    _dir = widget.downloadDir;
    _cookieBrowser = widget.cookieBrowser;
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDir() async {
    final path = await getDirectoryPath();
    if (path != null) setState(() => _dir = path);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _backendCtrl,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              border: OutlineInputBorder(),
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 20),
            Text('Download folder',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dir ?? 'Downloads folder (default)',
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(onPressed: _pickDir, child: const Text('Choose…')),
                if (_dir != null)
                  IconButton(
                    tooltip: 'Reset to Downloads',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dir = null),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Use cookies from',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _cookieBrowser,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                for (final b in _cookieBrowsers)
                  DropdownMenuItem(
                      value: b, child: Text(_cookieBrowserLabels[b]!)),
              ],
              onChanged: (v) =>
                  setState(() => _cookieBrowser = v ?? 'none'),
            ),
            const SizedBox(height: 4),
            Text(
              'For private posts (Instagram, X, Facebook), pick the browser '
              "you're logged in with. Cookies are sent only with your download "
              'and never stored on the server.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (
              backend: _backendCtrl.text.trim(),
              dir: _dir,
              cookieBrowser: _cookieBrowser,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

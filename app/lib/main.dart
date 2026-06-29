import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'saver.dart';

void main() => runApp(const VGetApp());

/// Default backend URL. Override in the UI (Settings) at runtime.
const _defaultBackend = 'http://localhost:8077';
const _prefBackend = 'backendUrl';
const _prefDownloadDir = 'downloadDir';

class VGetApp extends StatelessWidget {
  const VGetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VGet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
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
  late ApiClient _api = ApiClient(_backendUrl);

  Timer? _poll;
  JobStatus? _job;
  bool _busy = false;
  String? _message;

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
      _api = ApiClient(_backendUrl);
    });
  }

  Future<void> _saveSettings(String backendUrl, String? downloadDir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBackend, backendUrl);
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
    });

    try {
      final id = await _api.createJob(url);
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
                _message = 'Error: ${job.error ?? 'download failed'}';
              });
            }
          }
        } catch (e) {
          _poll?.cancel();
          setState(() {
            _busy = false;
            _message = 'Error: $e';
          });
        }
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _message = 'Error: $e';
      });
    }
  }

  Future<void> _onFinished(JobStatus job) async {
    try {
      final where = await saveResult(_api, job, downloadDir: _downloadDir);
      setState(() {
        _busy = false;
        _message = kIsWeb ? where : 'Saved to: $where';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _message = 'Saved on server, but local save failed: $e';
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
                    'Saving to: ${_downloadDir ?? 'Downloads folder'}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                if (job != null) ...[
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
                    color: _message!.startsWith('Error') ||
                            _message!.startsWith('Saved on server')
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(_message!.startsWith('Error') ||
                                  _message!.startsWith('Saved on server')
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
    final result = await showDialog<({String backend, String? dir})>(
      context: context,
      builder: (ctx) => _SettingsDialog(
        backendUrl: _backendUrl,
        downloadDir: _downloadDir,
      ),
    );
    if (result != null) {
      await _saveSettings(result.backend, result.dir);
    }
  }
}

/// Settings: backend URL + (desktop) download folder picker.
class _SettingsDialog extends StatefulWidget {
  final String backendUrl;
  final String? downloadDir;
  const _SettingsDialog({required this.backendUrl, this.downloadDir});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _backendCtrl =
      TextEditingController(text: widget.backendUrl);
  String? _dir;

  @override
  void initState() {
    super.initState();
    _dir = widget.downloadDir;
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
            (backend: _backendCtrl.text.trim(), dir: _dir),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

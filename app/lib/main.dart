import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api.dart';
import 'saver.dart';

void main() => runApp(const VGetApp());

/// Default backend URL. Override in the UI (Settings) at runtime.
const _defaultBackend = 'http://localhost:8077';

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
  final _backendCtrl = TextEditingController(text: _defaultBackend);
  late ApiClient _api = ApiClient(_defaultBackend);

  Timer? _poll;
  JobStatus? _job;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _poll?.cancel();
    _urlCtrl.dispose();
    _backendCtrl.dispose();
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
      _api = ApiClient(_backendCtrl.text.trim());
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
      final where = await saveResult(_api, job);
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
                    color: _message!.startsWith('Error')
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(_message!.startsWith('Error')
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

  void _openSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settings'),
        content: TextField(
          controller: _backendCtrl,
          decoration: const InputDecoration(
            labelText: 'Backend URL',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

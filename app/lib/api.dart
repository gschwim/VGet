import 'dart:convert';

import 'package:http/http.dart' as http;

/// Snapshot of a download job as reported by the backend.
class JobStatus {
  final String jobId;
  final String status; // queued | downloading | processing | finished | error
  final double progress; // 0..100
  final String? title;
  final String? filename;
  final String? error;

  const JobStatus({
    required this.jobId,
    required this.status,
    required this.progress,
    this.title,
    this.filename,
    this.error,
  });

  bool get isTerminal => status == 'finished' || status == 'error';
  bool get isFinished => status == 'finished';

  factory JobStatus.fromJson(Map<String, dynamic> j) => JobStatus(
        jobId: j['jobId'] as String,
        status: j['status'] as String,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        title: j['title'] as String?,
        filename: j['filename'] as String?,
        error: j['error'] as String?,
      );
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);
  @override
  String toString() => 'HTTP $statusCode: $body';
}

/// Thin client for the VGet backend.
class ApiClient {
  String baseUrl;
  String? token;

  ApiClient(this.baseUrl, {this.token});

  Map<String, String> get _authHeader =>
      token != null ? {'authorization': 'Bearer $token'} : const {};

  Future<String> createJob(String url, {String? format, String? cookies}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/jobs'),
      headers: {'content-type': 'application/json', ..._authHeader},
      body: jsonEncode({
        'url': url,
        if (format != null) 'format': format,
        if (cookies != null) 'cookies': cookies,
      }),
    );
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, resp.body);
    return jsonDecode(resp.body)['jobId'] as String;
  }

  Future<JobStatus> getJob(String id) async {
    final resp =
        await http.get(Uri.parse('$baseUrl/jobs/$id'), headers: _authHeader);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, resp.body);
    return JobStatus.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// URL for the produced file. Token is passed as a query param so that
  /// browser-initiated downloads (no custom headers) still authenticate.
  Uri fileUri(String id) {
    final q = token != null ? '?token=${Uri.encodeQueryComponent(token!)}' : '';
    return Uri.parse('$baseUrl/jobs/$id/file$q');
  }

  Future<bool> health() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/healthz'))
          .timeout(const Duration(seconds: 4));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

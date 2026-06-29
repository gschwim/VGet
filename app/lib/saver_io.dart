import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// Download the produced file to [downloadDir] (or the OS Downloads folder if
/// not set); returns the saved path.
Future<String> saveResult(ApiClient api, JobStatus job,
    {String? downloadDir}) async {
  Directory dir;
  if (downloadDir != null && downloadDir.trim().isNotEmpty) {
    dir = Directory(downloadDir.trim());
  } else {
    Directory? d;
    try {
      d = await getDownloadsDirectory();
    } catch (_) {
      d = null; // not supported on this platform
    }
    dir = d ?? await getApplicationDocumentsDirectory();
  }
  await dir.create(recursive: true);

  final resp = await http.get(api.fileUri(job.jobId));
  if (resp.statusCode != 200) {
    throw ApiException(resp.statusCode, resp.body);
  }
  final file = File('${dir.path}/${job.filename ?? job.jobId}');
  await file.writeAsBytes(resp.bodyBytes);
  return file.path;
}

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

/// The OS Downloads folder path (used when no custom folder is set), or null.
Future<String?> defaultDownloadLocation() async {
  try {
    return (await getDownloadsDirectory())?.path;
  } catch (_) {
    return null;
  }
}

/// Collapse a leading $HOME to '~' for display; otherwise return as-is.
String prettyPath(String path) {
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty && path.startsWith(home)) {
    final rest = path.substring(home.length);
    return rest.isEmpty ? '~' : '~$rest';
  }
  return path;
}

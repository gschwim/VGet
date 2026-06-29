import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// Download the produced file to the user's Downloads folder; returns its path.
Future<String> saveResult(ApiClient api, JobStatus job) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null; // not supported on this platform
  }
  dir ??= await getApplicationDocumentsDirectory();

  final resp = await http.get(api.fileUri(job.jobId));
  if (resp.statusCode != 200) {
    throw ApiException(resp.statusCode, resp.body);
  }
  final file = File('${dir.path}/${job.filename ?? job.jobId}');
  await file.writeAsBytes(resp.bodyBytes);
  return file.path;
}

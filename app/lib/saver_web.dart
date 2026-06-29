import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// On web, let the browser handle the download via the file URL. [downloadDir]
/// is ignored — the browser controls where downloads land.
Future<String> saveResult(ApiClient api, JobStatus job,
    {String? downloadDir}) async {
  await launchUrl(api.fileUri(job.jobId), webOnlyWindowName: '_blank');
  return 'Started download in your browser';
}

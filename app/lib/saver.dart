// Saves a finished job's file, dispatching to a platform implementation:
//   - native (dart:io): downloads bytes to the Downloads folder
//   - web: hands the URL to the browser to download
export 'saver_io.dart' if (dart.library.html) 'saver_web.dart';

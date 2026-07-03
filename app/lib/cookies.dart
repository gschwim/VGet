// Browser cookie extraction, dispatched per platform:
//   - native (dart:io): reads the local browser cookie store
//   - web: no-op (browser sandbox forbids cross-site cookie access)
export 'cookies_io.dart' if (dart.library.html) 'cookies_web.dart';

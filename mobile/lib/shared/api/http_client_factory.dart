import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../demo/demo_backend.dart';

/// The one place an HTTP client is created for backend traffic (ApiClient
/// and the signed-URL upload helpers). In a demo build it is the in-app
/// DemoBackend; otherwise a plain network client.
http.Client createHttpClient() => AppConfig.demoMode ? DemoBackend.instance.httpClient : http.Client();

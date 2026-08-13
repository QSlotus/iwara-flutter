export 'package:signal_desk/core/edge/edge_models.dart';

class ApiOperation {
  ApiOperation({
    required this.operation,
    required this.method,
    required this.host,
    required this.route,
    this.scope = 'core',
    this.body = false,
  });

  final String operation;
  final String method;
  final String host;
  final String route;
  final String scope;
  final bool body;

  factory ApiOperation.fromJson(Map<String, dynamic> json) {
    return ApiOperation(
      operation: json['operation'] as String,
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      host: json['host'] as String? ?? 'api.iwara.tv',
      route: json['route'] as String? ?? '/',
      scope: json['scope'] as String? ?? 'core',
      body: json['body'] == true,
    );
  }
}

class PlayableMediaSource {
  PlayableMediaSource({required this.label, required this.url, this.downloadUrl});
  final String label;
  final String url;
  final String? downloadUrl;
}

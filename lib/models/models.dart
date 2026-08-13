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

class EdgeProbeResult {
  EdgeProbeResult({
    required this.ip,
    required this.latencyMs,
    required this.lossRate,
    required this.sent,
    required this.received,
  });

  final String ip;
  final double latencyMs;
  final double lossRate;
  final int sent;
  final int received;

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'latencyMs': latencyMs,
        'lossRate': lossRate,
        'sent': sent,
        'received': received,
      };
}

class EdgeStatus {
  EdgeStatus({
    required this.status,
    required this.activeIp,
    required this.configuredIp,
    this.fastestIp,
    this.selectedIp,
    this.selectionMode = 'configured',
    this.source,
    this.warning,
    this.durationMs,
    this.results = const [],
  });

  final String status;
  final String activeIp;
  final String configuredIp;
  final String? fastestIp;
  final String? selectedIp;
  final String selectionMode;
  final String? source;
  final String? warning;
  final int? durationMs;
  final List<EdgeProbeResult> results;

  Map<String, dynamic> toJson() => {
        'status': status,
        'activeIp': activeIp,
        'configuredIp': configuredIp,
        'fastestIp': fastestIp,
        'selectedIp': selectedIp,
        'selectionMode': selectionMode,
        'source': source,
        'warning': warning,
        'durationMs': durationMs,
        'results': results.map((e) => e.toJson()).toList(),
      };
}

class PlayableMediaSource {
  PlayableMediaSource({required this.label, required this.url, this.downloadUrl});
  final String label;
  final String url;
  final String? downloadUrl;
}

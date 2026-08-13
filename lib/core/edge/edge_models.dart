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

  factory EdgeProbeResult.fromJson(Map<String, dynamic> json) {
    return EdgeProbeResult(
      ip: '${json['ip'] ?? ''}',
      latencyMs: (json['latencyMs'] is num) ? (json['latencyMs'] as num).toDouble() : double.tryParse('${json['latencyMs']}') ?? 0,
      lossRate: (json['lossRate'] is num) ? (json['lossRate'] as num).toDouble() : double.tryParse('${json['lossRate']}') ?? 0,
      sent: int.tryParse('${json['sent'] ?? 0}') ?? 0,
      received: int.tryParse('${json['received'] ?? 0}') ?? 0,
    );
  }
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

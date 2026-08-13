import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/models.dart';

class EdgeProbeService {
  Future<List<EdgeProbeResult>> run({
    required String configuredIp,
    int limit = 10,
  }) async {
    final ips = await _sampleIps(configuredIp: configuredIp, limit: max(limit * 4, 40));
    final results = <EdgeProbeResult>[];
    for (final ip in ips) {
      final sw = Stopwatch()..start();
      var ok = false;
      try {
        final socket = await Socket.connect(ip, 443, timeout: const Duration(milliseconds: 1200));
        ok = true;
        await socket.close();
      } catch (_) {
        ok = false;
      }
      sw.stop();
      if (!ok) continue;
      results.add(EdgeProbeResult(
        ip: ip,
        latencyMs: sw.elapsedMicroseconds / 1000.0,
        lossRate: 0,
        sent: 1,
        received: 1,
      ));
      if (results.length >= limit) break;
    }
    results.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    if (results.isEmpty && configuredIp.isNotEmpty) {
      results.add(EdgeProbeResult(
        ip: configuredIp,
        latencyMs: 9999,
        lossRate: 1,
        sent: 1,
        received: 0,
      ));
    }
    return results.take(limit).toList();
  }

  Future<List<String>> _sampleIps({required String configuredIp, required int limit}) async {
    final text = await rootBundle.loadString('assets/cloudflare-ip-ranges.txt');
    final ranges = text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
    final random = Random();
    final out = <String>{};
    if (configuredIp.isNotEmpty) out.add(configuredIp);
    for (final range in ranges) {
      final sampled = _sampleFromCidr(range, random);
      if (sampled != null) out.add(sampled);
      if (out.length >= limit) break;
    }
    // also add a few nearby from configured ip if possible
    return out.take(limit).toList();
  }

  String? _sampleFromCidr(String cidr, Random random) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final base = parts[0].split('.');
    if (base.length != 4) return null;
    final prefix = int.tryParse(parts[1]) ?? 32;
    if (prefix < 0 || prefix > 32) return null;
    final baseNum = (int.parse(base[0]) << 24) + (int.parse(base[1]) << 16) + (int.parse(base[2]) << 8) + int.parse(base[3]);
    final hostBits = 32 - prefix;
    if (hostBits <= 0) return parts[0];
    final maxHost = (1 << min(hostBits, 16)) - 1;
    final offset = random.nextInt(max(1, maxHost));
    final value = baseNum + offset;
    return [
      (value >> 24) & 255,
      (value >> 16) & 255,
      (value >> 8) & 255,
      value & 255,
    ].join('.');
  }
}

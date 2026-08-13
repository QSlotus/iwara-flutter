import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/models.dart';

class ApiCatalog {
  ApiCatalog(this.operations, this.auxiliary);

  final Map<String, ApiOperation> operations;
  final Map<String, ApiOperation> auxiliary;

  static Future<ApiCatalog> load() async {
    final raw = await rootBundle.loadString('assets/IWARA_API_INDEX.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final ops = <String, ApiOperation>{};
    for (final item in (json['operations'] as List? ?? const [])) {
      final map = Map<String, dynamic>.from(item as Map);
      final op = ApiOperation.fromJson(map);
      if (op.scope == 'admin' || op.route.startsWith('/admin/') || op.host.startsWith('dynamic:')) {
        continue;
      }
      ops[op.operation] = op;
    }
    final aux = <String, ApiOperation>{};
    for (final item in (json['ancillaryOperations'] as List? ?? const [])) {
      final map = Map<String, dynamic>.from(item as Map);
      final op = ApiOperation.fromJson(map);
      if (op.operation == 'fetchAdZones' || op.operation == 'fetchSignedFile') {
        aux[op.operation] = op;
      }
    }
    return ApiCatalog(ops, aux);
  }
}

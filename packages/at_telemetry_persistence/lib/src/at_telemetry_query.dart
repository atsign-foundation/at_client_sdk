enum AtTelemetryOrder {
  newestFirst,
  oldestFirst,
}

final class AtTelemetryQuery {
  final String tenantId;
  final String? name;
  final DateTime? startTime;
  final DateTime? endTime;
  final int limit;
  final int offset;
  final AtTelemetryOrder order;

  AtTelemetryQuery({
    required this.tenantId,
    this.name,
    this.startTime,
    this.endTime,
    this.limit = 100,
    this.offset = 0,
    this.order = AtTelemetryOrder.newestFirst,
  }) {
    if (tenantId.trim().isEmpty) {
      throw ArgumentError.value(tenantId, 'tenantId', 'must not be empty');
    }
    if (name != null && name!.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (startTime != null && endTime != null && startTime!.isAfter(endTime!)) {
      throw ArgumentError.value(
        endTime,
        'endTime',
        'must not be before startTime',
      );
    }
    if (limit < 1 || limit > 1000) {
      throw RangeError.range(limit, 1, 1000, 'limit');
    }
    if (offset < 0) {
      throw RangeError.range(offset, 0, null, 'offset');
    }
  }
}

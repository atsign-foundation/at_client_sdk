enum AtTelemetryOrder {
  newestFirst,
  oldestFirst,
}

final class AtTelemetryQuery {
  static const String nameParameter = 'name';
  static const String startTimeParameter = 'start';
  static const String endTimeParameter = 'end';
  static const String limitParameter = 'limit';
  static const String offsetParameter = 'offset';
  static const String orderParameter = 'order';

  static const Set<String> _parameters = <String>{
    nameParameter,
    startTimeParameter,
    endTimeParameter,
    limitParameter,
    offsetParameter,
    orderParameter,
  };

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

  factory AtTelemetryQuery.fromQueryParameters({
    required String tenantId,
    required Map<String, String> parameters,
  }) {
    for (final String key in parameters.keys) {
      if (!_parameters.contains(key)) {
        throw FormatException('Unsupported query parameter: $key');
      }
    }

    final String? order = parameters[orderParameter];
    return AtTelemetryQuery(
      tenantId: tenantId,
      name: parameters[nameParameter],
      startTime: _parseTime(parameters[startTimeParameter]),
      endTime: _parseTime(parameters[endTimeParameter]),
      limit: _parseInt(parameters[limitParameter]) ?? 100,
      offset: _parseInt(parameters[offsetParameter]) ?? 0,
      order: order == null
          ? AtTelemetryOrder.newestFirst
          : AtTelemetryOrder.values.firstWhere(
              (AtTelemetryOrder value) => value.name == order,
              orElse: () => throw FormatException(
                'order must be one of '
                '${AtTelemetryOrder.values.map((AtTelemetryOrder value) => value.name).join(', ')}',
              ),
            ),
    );
  }

  Map<String, String> toQueryParameters() {
    return <String, String>{
      if (name != null) nameParameter: name!,
      if (startTime != null)
        startTimeParameter: startTime!.toUtc().toIso8601String(),
      if (endTime != null) endTimeParameter: endTime!.toUtc().toIso8601String(),
      limitParameter: '$limit',
      offsetParameter: '$offset',
      orderParameter: order.name,
    };
  }

  static DateTime? _parseTime(String? value) {
    return value == null ? null : DateTime.parse(value).toUtc();
  }

  static int? _parseInt(String? value) {
    return value == null ? null : int.parse(value);
  }
}

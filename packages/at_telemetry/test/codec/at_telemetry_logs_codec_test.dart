import 'dart:typed_data';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:dartastic_opentelemetry/proto/collector/logs/v1/logs_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/logs/v1/logs.pb.dart' as logs;
import 'package:dartastic_opentelemetry/proto/resource/v1/resource.pb.dart'
    as otel_resource;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

void main() {
  const AtTelemetryLogsCodec codec = AtTelemetryLogsCodec();
  final DateTime observedAt = DateTime.utc(2024, 6, 1, 12);

  AtTelemetryLogRecord roundTrip(
    AtTelemetryLogRecord record, {
    AtTelemetryResource? resource,
  }) {
    return codec
        .decodeExportRequest(codec.encodeExportRequest(
          <AtTelemetryLogRecord>[record],
          resource: resource,
          observedAt: observedAt,
        ))
        .single;
  }

  common.KeyValue stringAttribute(String key, String value) {
    return common.KeyValue(
      key: key,
      value: common.AnyValue(stringValue: value),
    );
  }

  List<int> rawRequest({
    List<common.KeyValue> resourceAttributes = const <common.KeyValue>[],
    List<common.KeyValue> scopeAttributes = const <common.KeyValue>[],
    required List<logs.LogRecord> logRecords,
  }) {
    return collector.ExportLogsServiceRequest(
      resourceLogs: <logs.ResourceLogs>[
        logs.ResourceLogs(
          resource: otel_resource.Resource(attributes: resourceAttributes),
          scopeLogs: <logs.ScopeLogs>[
            logs.ScopeLogs(
              scope: common.InstrumentationScope(
                name: 'scope',
                attributes: scopeAttributes,
              ),
              logRecords: logRecords,
            ),
          ],
        ),
      ],
    ).writeToBuffer();
  }

  group('AtTelemetryLogsCodec', () {
    group('round trip', () {
      test('keeps every field of an Event', () {
        final AtTelemetryLogRecord decoded = roundTrip(
          AtTelemetryLogRecord(
            eventName: 'login',
            body: 'hello',
            timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7),
            severityNumber: AtTelemetrySeverity.warn2,
            severityText: 'WARN2',
            attributes: const <String, Object?>{'method': 'pkam'},
          ),
        );

        expect(decoded.eventName, 'login');
        expect(decoded.body, 'hello');
        expect(decoded.timestamp, DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7));
        expect(decoded.severityNumber, AtTelemetrySeverity.warn2);
        expect(decoded.severityText, 'WARN2');
        expect(decoded.attributes, <String, Object?>{'method': 'pkam'});
      });

      test('keeps every AnyValue type', () {
        final Map<String, Object?> attributes = <String, Object?>{
          'string': 'a',
          'bool': true,
          'int': 42,
          'negative': -7,
          'max int': 0x7fffffffffffffff,
          'double': 1.5,
          'list': <Object?>[1, 'a', false],
          'map': <String, Object?>{
            'nested': <String, Object?>{'deep': 2.5},
          },
        };

        final AtTelemetryLogRecord decoded =
            roundTrip(AtTelemetryLogRecord(attributes: attributes));

        expect(decoded.attributes, attributes);
      });

      test('keeps a Uint8List as a Uint8List', () {
        final AtTelemetryLogRecord decoded = roundTrip(
          AtTelemetryLogRecord(body: Uint8List.fromList(<int>[0, 1, 255])),
        );

        expect(decoded.body, isA<Uint8List>());
        expect(decoded.body, <int>[0, 1, 255]);
      });

      test('keeps null inside a list but drops null attributes', () {
        final AtTelemetryLogRecord decoded = roundTrip(
          AtTelemetryLogRecord(
            attributes: const <String, Object?>{
              'missing': null,
              'list': <Object?>[1, null],
              'map': <String, Object?>{'missing': null, 'kept': 1},
            },
          ),
        );

        expect(decoded.attributes, <String, Object?>{
          'list': <Object?>[1, null],
          'map': <String, Object?>{'kept': 1},
        });
      });

      test('keeps every severity level', () {
        for (final AtTelemetrySeverity severity in AtTelemetrySeverity.values) {
          expect(
            roundTrip(AtTelemetryLogRecord(severityNumber: severity))
                .severityNumber,
            severity,
          );
        }
      });

      test('decodes nested lists and maps as unmodifiable', () {
        final AtTelemetryLogRecord decoded = roundTrip(
          AtTelemetryLogRecord(
            body: <String, Object?>{
              'list': <Object?>[1],
            },
          ),
        );
        final Map<String, Object?> body = decoded.body! as Map<String, Object?>;

        expect(() => body['x'] = 1, throwsUnsupportedError);
        expect(
          () => (body['list']! as List<Object?>).add(2),
          throwsUnsupportedError,
        );
      });

      test('keeps the order of several records', () {
        final List<AtTelemetryLogRecord> decoded = codec.decodeExportRequest(
          codec.encodeExportRequest(<AtTelemetryLogRecord>[
            AtTelemetryLogRecord(body: 'first'),
            AtTelemetryLogRecord(body: 'second'),
            AtTelemetryLogRecord(body: 'third'),
          ]),
        );

        expect(
          decoded.map((AtTelemetryLogRecord record) => record.body),
          <Object?>['first', 'second', 'third'],
        );
      });

      test('merges resource attributes into each record', () {
        final AtTelemetryLogRecord decoded = roundTrip(
          AtTelemetryLogRecord(
            attributes: const <String, Object?>{'shared': 'record'},
          ),
          resource: AtTelemetryResource(
            serviceName: 'svc',
            attributes: const <String, Object?>{
              'shared': 'resource',
              'atsign': '@alice',
            },
          ),
        );

        expect(decoded.attributes, <String, Object?>{
          'shared': 'record',
          'atsign': '@alice',
          AtTelemetryResource.serviceNameAttribute: 'svc',
        });
      });
    });

    group('event name', () {
      test('travels as the event.name attribute', () {
        final collector.ExportLogsServiceRequest request =
            collector.ExportLogsServiceRequest.fromBuffer(
          codec.encodeExportRequest(<AtTelemetryLogRecord>[
            AtTelemetryLogRecord(eventName: 'login'),
          ]),
        );
        final logs.LogRecord logRecord =
            request.resourceLogs.single.scopeLogs.single.logRecords.single;

        expect(logRecord.attributes.single.key,
            AtTelemetryLogsCodec.eventNameAttribute);
        expect(logRecord.attributes.single.value.stringValue, 'login');
      });

      test('eventName wins over an event.name attribute on an Event', () {
        final AtTelemetryLogRecord decoded = roundTrip(
          AtTelemetryLogRecord(
            eventName: 'login',
            attributes: const <String, Object?>{
              AtTelemetryLogsCodec.eventNameAttribute: 'other',
            },
          ),
        );

        expect(decoded.eventName, 'login');
        expect(decoded.attributes, isEmpty);
      });

      test('an empty eventName decodes as a plain log', () {
        final AtTelemetryLogRecord decoded =
            roundTrip(AtTelemetryLogRecord(eventName: '', body: 'x'));

        expect(decoded.eventName, isNull);
        expect(decoded.isEvent, isFalse);
      });

      test('a plain log with an event.name attribute decodes as an Event', () {
        final AtTelemetryLogRecord decoded = roundTrip(
          AtTelemetryLogRecord(
            attributes: const <String, Object?>{
              AtTelemetryLogsCodec.eventNameAttribute: 'login',
            },
          ),
        );

        expect(decoded.eventName, 'login');
        expect(decoded.attributes, isEmpty);
      });

      test('throws FormatException for a non-string event.name', () {
        expect(
          () => codec.decodeExportRequest(rawRequest(
            logRecords: <logs.LogRecord>[
              logs.LogRecord(attributes: <common.KeyValue>[
                common.KeyValue(
                  key: AtTelemetryLogsCodec.eventNameAttribute,
                  value: common.AnyValue(intValue: Int64(1)),
                ),
              ]),
            ],
          )),
          throwsFormatException,
        );
      });
    });

    group('timestamps', () {
      test('uses observedAt for a record without a timestamp', () {
        final collector.ExportLogsServiceRequest request =
            collector.ExportLogsServiceRequest.fromBuffer(
          codec.encodeExportRequest(
            <AtTelemetryLogRecord>[AtTelemetryLogRecord()],
            observedAt: observedAt,
          ),
        );
        final logs.LogRecord logRecord =
            request.resourceLogs.single.scopeLogs.single.logRecords.single;
        final Int64 nanoseconds =
            Int64(observedAt.microsecondsSinceEpoch) * 1000;

        expect(logRecord.timeUnixNano, nanoseconds);
        expect(logRecord.observedTimeUnixNano, nanoseconds);
      });

      test('decodes observedTimeUnixNano when timeUnixNano is 0', () {
        final AtTelemetryLogRecord decoded = codec
            .decodeExportRequest(rawRequest(
              logRecords: <logs.LogRecord>[
                logs.LogRecord(
                  observedTimeUnixNano:
                      Int64(observedAt.microsecondsSinceEpoch) * 1000,
                ),
              ],
            ))
            .single;

        expect(decoded.timestamp, observedAt);
      });

      test('decodes a null timestamp when both are 0', () {
        final AtTelemetryLogRecord decoded = codec
            .decodeExportRequest(rawRequest(
              logRecords: <logs.LogRecord>[logs.LogRecord()],
            ))
            .single;

        expect(decoded.timestamp, isNull);
      });
    });

    group('decodeExportRequest', () {
      test('merges resource, scope and record attributes in that order', () {
        final AtTelemetryLogRecord decoded = codec
            .decodeExportRequest(rawRequest(
              resourceAttributes: <common.KeyValue>[
                stringAttribute('shared', 'resource'),
                stringAttribute('resource', 'r'),
              ],
              scopeAttributes: <common.KeyValue>[
                stringAttribute('shared', 'scope'),
                stringAttribute('scope', 's'),
              ],
              logRecords: <logs.LogRecord>[
                logs.LogRecord(attributes: <common.KeyValue>[
                  stringAttribute('shared', 'record'),
                ]),
              ],
            ))
            .single;

        expect(decoded.attributes, <String, Object?>{
          'shared': 'record',
          'resource': 'r',
          'scope': 's',
        });
      });

      test('decodes an unspecified severity as null', () {
        final AtTelemetryLogRecord decoded = codec
            .decodeExportRequest(rawRequest(
              logRecords: <logs.LogRecord>[
                logs.LogRecord(
                  severityNumber:
                      logs.SeverityNumber.SEVERITY_NUMBER_UNSPECIFIED,
                ),
              ],
            ))
            .single;

        expect(decoded.severityNumber, isNull);
        expect(decoded.severityText, isNull);
      });

      test('decodes an unknown severity number as null', () {
        // resourceLogs { scopeLogs { logRecords { severityNumber: 25 } } }
        final List<int> payload = <int>[
          0x0a, 0x06, 0x12, 0x04, 0x12, 0x02, 0x10, 0x19, //
        ];

        expect(
          codec.decodeExportRequest(payload).single.severityNumber,
          isNull,
        );
      });

      test('throws FormatException for bytes that are not Protobuf', () {
        expect(
          () => codec.decodeExportRequest(<int>[0xff, 0xff, 0xff]),
          throwsFormatException,
        );
      });

      test('throws FormatException for a request with no records', () {
        expect(() => codec.decodeExportRequest(<int>[]), throwsFormatException);
        expect(
          () => codec.decodeExportRequest(
            rawRequest(logRecords: const <logs.LogRecord>[]),
          ),
          throwsFormatException,
        );
      });
    });

    group('encodeExportRequest', () {
      test('throws ArgumentError for no records', () {
        expect(
          () => codec.encodeExportRequest(const <AtTelemetryLogRecord>[]),
          throwsArgumentError,
        );
      });

      test('names the instrumentation scope at_telemetry', () {
        final collector.ExportLogsServiceRequest request =
            collector.ExportLogsServiceRequest.fromBuffer(
          codec.encodeExportRequest(
            <AtTelemetryLogRecord>[AtTelemetryLogRecord()],
          ),
        );
        final logs.ResourceLogs resourceLogs = request.resourceLogs.single;

        expect(resourceLogs.scopeLogs.single.scope.name,
            AtTelemetryLogsCodec.scopeName);
        expect(resourceLogs.resource.attributes, isEmpty);
      });

      test('writes the resource attributes on the resource', () {
        final collector.ExportLogsServiceRequest request =
            collector.ExportLogsServiceRequest.fromBuffer(
          codec.encodeExportRequest(
            <AtTelemetryLogRecord>[AtTelemetryLogRecord()],
            resource: AtTelemetryResource(serviceName: 'svc'),
          ),
        );
        final common.KeyValue attribute =
            request.resourceLogs.single.resource.attributes.single;

        expect(attribute.key, AtTelemetryResource.serviceNameAttribute);
        expect(attribute.value.stringValue, 'svc');
      });
    });

    test('encodeExportResponse is a valid empty response', () {
      final collector.ExportLogsServiceResponse response =
          collector.ExportLogsServiceResponse.fromBuffer(
        codec.encodeExportResponse(),
      );

      expect(response.hasPartialSuccess(), isFalse);
    });
  });
}

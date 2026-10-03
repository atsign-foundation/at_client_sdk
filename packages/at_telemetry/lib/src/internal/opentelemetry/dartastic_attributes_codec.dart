import 'dart:convert';

import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:fixnum/fixnum.dart';

final class DartasticAttributesCodec {
  const DartasticAttributesCodec();

  List<common.KeyValue> encode(Map<String, Object?> attributes) {
    return <common.KeyValue>[
      for (final MapEntry<String, Object?> entry in attributes.entries)
        if (entry.value != null)
          common.KeyValue(
            key: entry.key,
            value: _encodeValue(entry.value),
          ),
    ];
  }

  Map<String, Object?> decode(Iterable<common.KeyValue> attributes) {
    return <String, Object?>{
      for (final common.KeyValue attribute in attributes)
        attribute.key: _decodeValue(attribute.value),
    };
  }

  common.AnyValue _encodeValue(Object? value) {
    return switch (value) {
      final String value => common.AnyValue(stringValue: value),
      final bool value => common.AnyValue(boolValue: value),
      final int value => common.AnyValue(intValue: Int64(value)),
      final double value => common.AnyValue(doubleValue: _finite(value)),
      final List<Object?> values => common.AnyValue(
          arrayValue: common.ArrayValue(
            values: values.map<common.AnyValue>(_encodeValue),
          ),
        ),
      final Map<String, Object?> values => common.AnyValue(
          kvlistValue: common.KeyValueList(values: encode(values)),
        ),
      _ => throw ArgumentError.value(
          value,
          'attributes',
          'values must be String, bool, int, double, List, or Map',
        ),
    };
  }

  Object? _decodeValue(common.AnyValue value) {
    return switch (value.whichValue()) {
      common.AnyValue_Value.stringValue => value.stringValue,
      common.AnyValue_Value.boolValue => value.boolValue,
      common.AnyValue_Value.intValue => value.intValue.toInt(),
      common.AnyValue_Value.doubleValue => _finite(value.doubleValue),
      common.AnyValue_Value.arrayValue => List<Object?>.unmodifiable(
          value.arrayValue.values.map<Object?>(_decodeValue),
        ),
      common.AnyValue_Value.kvlistValue => Map<String, Object?>.unmodifiable(
          decode(value.kvlistValue.values),
        ),
      common.AnyValue_Value.bytesValue => base64Encode(value.bytesValue),
      common.AnyValue_Value.notSet => throw const FormatException(
          'OTLP attribute value must be set',
        ),
    };
  }

  double _finite(double value) {
    if (!value.isFinite) {
      throw const FormatException(
        'OTLP double attributes must be finite',
      );
    }
    return value;
  }
}

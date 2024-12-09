import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

const JsonEncoder jsonPrettyPrinter = JsonEncoder.withIndent('    ');

@JsonSerializable(explicitToJson: true)
class PolicyIntent {
  final String intent;
  final Map<String, dynamic>? params;

  PolicyIntent({
    required this.intent,
    this.params,
  });

  Map<String, dynamic> toJson() => _$PolicyIntentToJson(this);

  static PolicyIntent fromJson(Map<String, dynamic> json) =>
      _$PolicyIntentFromJson(json);

  @override
  String toString() => jsonPrettyPrinter.convert(toJson());
}

@JsonSerializable(explicitToJson: true)
class PolicyDetail {
  final String intent;
  Map<String, dynamic> info;

  PolicyDetail({
    required this.intent,
    required this.info,
  });

  Map<String, dynamic> toJson() => _$PolicyDetailToJson(this);

  static PolicyDetail fromJson(Map<String, dynamic> json) =>
      _$PolicyDetailFromJson(json);

  @override
  String toString() => jsonPrettyPrinter.convert(toJson());
}

@JsonSerializable(explicitToJson: true)
class PolicyRequest {
  final String serviceAtsign;
  final String serviceName;
  final String serviceGroupName;
  final String clientAtsign;
  final List<PolicyIntent> intents;

  PolicyRequest({
    required this.serviceAtsign,
    required this.serviceName,
    required this.serviceGroupName,
    required this.clientAtsign,
    required this.intents,
  });

  Map<String, dynamic> toJson() => _$PolicyRequestToJson(this);

  static PolicyRequest fromJson(Map<String, dynamic> json) =>
      _$PolicyRequestFromJson(json);

  @override
  String toString() => jsonPrettyPrinter.convert(toJson());
}

@JsonSerializable(explicitToJson: true)
class PolicyResponse {
  final String? message;
  final List<PolicyDetail> policyDetails;

  PolicyResponse({
    required this.message,
    required this.policyDetails,
  }) {
    Set<String> intents = {};
    for (final i in policyDetails) {
      if (intents.contains(i.intent)) {
        throw IllegalArgumentException(
            'More than one PolicyDetail provided for intent: ${i.intent}');
      } else {
        intents.add(i.intent);
      }
    }
  }

  PolicyDetail? infoForIntent(String intent) {
    for (final i in policyDetails) {
      if (i.intent == intent) {
        return i;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => _$PolicyResponseToJson(this);

  static PolicyResponse fromJson(Map<String, dynamic> json) =>
      _$PolicyResponseFromJson(json);

  @override
  String toString() => jsonPrettyPrinter.convert(toJson());
}

abstract class CoreServiceInfo {
  final int timestamp;
  final String serviceAtsign;
  final String? policyAtsign;
  final String serviceName;
  final String serviceGroupName;

  CoreServiceInfo({
    required this.timestamp,
    required this.serviceAtsign,
    required this.policyAtsign,
    required this.serviceName,
    required this.serviceGroupName,
  });
}

enum PolicyLogEventType {
  request,
  response,
  decision,
}

@JsonSerializable(explicitToJson: true)
class PolicyLogEvent extends CoreServiceInfo {
  final String clientAtsign;
  final PolicyLogEventType eventType;
  final String? message;
  final Map<String, dynamic> eventDetails;

  PolicyLogEvent({
    required super.timestamp,
    required super.serviceAtsign,
    required super.policyAtsign,
    required super.serviceName,
    required super.serviceGroupName,
    required this.clientAtsign,
    required this.eventType,
    required this.eventDetails,
    required this.message,
  });

  Map<String, dynamic> toJson() => _$PolicyLogEventToJson(this);

  static PolicyLogEvent fromJson(Map<String, dynamic> json) =>
      _$PolicyLogEventFromJson(json);

  @override
  String toString() => jsonPrettyPrinter.convert(toJson());
}

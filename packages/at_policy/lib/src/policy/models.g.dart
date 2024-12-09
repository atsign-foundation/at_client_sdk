// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PolicyIntent _$PolicyIntentFromJson(Map<String, dynamic> json) => PolicyIntent(
      intent: json['intent'] as String,
      params: json['params'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$PolicyIntentToJson(PolicyIntent instance) =>
    <String, dynamic>{
      'intent': instance.intent,
      'params': instance.params,
    };

PolicyDetail _$PolicyDetailFromJson(Map<String, dynamic> json) => PolicyDetail(
      intent: json['intent'] as String,
      info: json['info'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$PolicyDetailToJson(PolicyDetail instance) =>
    <String, dynamic>{
      'intent': instance.intent,
      'info': instance.info,
    };

PolicyRequest _$PolicyRequestFromJson(Map<String, dynamic> json) =>
    PolicyRequest(
      serviceAtsign: json['serviceAtsign'] as String,
      serviceName: json['serviceName'] as String,
      serviceGroupName: json['serviceGroupName'] as String,
      clientAtsign: json['clientAtsign'] as String,
      intents: (json['intents'] as List<dynamic>)
          .map((e) => PolicyIntent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PolicyRequestToJson(PolicyRequest instance) =>
    <String, dynamic>{
      'serviceAtsign': instance.serviceAtsign,
      'serviceName': instance.serviceName,
      'serviceGroupName': instance.serviceGroupName,
      'clientAtsign': instance.clientAtsign,
      'intents': instance.intents.map((e) => e.toJson()).toList(),
    };

PolicyResponse _$PolicyResponseFromJson(Map<String, dynamic> json) =>
    PolicyResponse(
      message: json['message'] as String?,
      policyDetails: (json['policyDetails'] as List<dynamic>)
          .map((e) => PolicyDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PolicyResponseToJson(PolicyResponse instance) =>
    <String, dynamic>{
      'message': instance.message,
      'policyDetails': instance.policyDetails.map((e) => e.toJson()).toList(),
    };

PolicyLogEvent _$PolicyLogEventFromJson(Map<String, dynamic> json) =>
    PolicyLogEvent(
      timestamp: (json['timestamp'] as num).toInt(),
      serviceAtsign: json['serviceAtsign'] as String,
      policyAtsign: json['policyAtsign'] as String?,
      serviceName: json['serviceName'] as String,
      serviceGroupName: json['serviceGroupName'] as String,
      clientAtsign: json['clientAtsign'] as String,
      eventType: $enumDecode(_$PolicyLogEventTypeEnumMap, json['eventType']),
      eventDetails: json['eventDetails'] as Map<String, dynamic>,
      message: json['message'] as String?,
    );

Map<String, dynamic> _$PolicyLogEventToJson(PolicyLogEvent instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp,
      'serviceAtsign': instance.serviceAtsign,
      'policyAtsign': instance.policyAtsign,
      'serviceName': instance.serviceName,
      'serviceGroupName': instance.serviceGroupName,
      'clientAtsign': instance.clientAtsign,
      'eventType': _$PolicyLogEventTypeEnumMap[instance.eventType]!,
      'message': instance.message,
      'eventDetails': instance.eventDetails,
    };

const _$PolicyLogEventTypeEnumMap = {
  PolicyLogEventType.request: 'request',
  PolicyLogEventType.response: 'response',
  PolicyLogEventType.decision: 'decision',
};

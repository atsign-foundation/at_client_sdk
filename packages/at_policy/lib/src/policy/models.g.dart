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

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
      timestamp: (json['timestamp'] as num).toInt(),
      deviceAtsign: json['deviceAtsign'] as String,
      policyAtsign: json['policyAtsign'] as String?,
      devicename: json['devicename'] as String,
      deviceGroupName: json['deviceGroupName'] as String,
      managerAtsigns: (json['managerAtsigns'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      version: json['version'] as String,
      corePackageVersion: json['corePackageVersion'] as String,
      supportedFeatures: json['supportedFeatures'] as Map<String, dynamic>,
      allowedServices: (json['allowedServices'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      status: json['status'] as String?,
    );

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp,
      'deviceAtsign': instance.deviceAtsign,
      'policyAtsign': instance.policyAtsign,
      'devicename': instance.devicename,
      'deviceGroupName': instance.deviceGroupName,
      'managerAtsigns': instance.managerAtsigns,
      'version': instance.version,
      'corePackageVersion': instance.corePackageVersion,
      'supportedFeatures': instance.supportedFeatures,
      'allowedServices': instance.allowedServices,
      'status': instance.status,
    };

PolicyLogEvent _$PolicyLogEventFromJson(Map<String, dynamic> json) =>
    PolicyLogEvent(
      timestamp: (json['timestamp'] as num).toInt(),
      deviceAtsign: json['deviceAtsign'] as String,
      policyAtsign: json['policyAtsign'] as String?,
      devicename: json['devicename'] as String,
      deviceGroupName: json['deviceGroupName'] as String,
      clientAtsign: json['clientAtsign'] as String,
      eventType: $enumDecode(_$PolicyLogEventTypeEnumMap, json['eventType']),
      eventDetails: json['eventDetails'] as Map<String, dynamic>,
      message: json['message'] as String?,
    );

Map<String, dynamic> _$PolicyLogEventToJson(PolicyLogEvent instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp,
      'deviceAtsign': instance.deviceAtsign,
      'policyAtsign': instance.policyAtsign,
      'devicename': instance.devicename,
      'deviceGroupName': instance.deviceGroupName,
      'clientAtsign': instance.clientAtsign,
      'eventType': _$PolicyLogEventTypeEnumMap[instance.eventType]!,
      'message': instance.message,
      'eventDetails': instance.eventDetails,
    };

const _$PolicyLogEventTypeEnumMap = {
  PolicyLogEventType.requestFromDevice: 'requestFromDevice',
  PolicyLogEventType.responseToDevice: 'responseToDevice',
  PolicyLogEventType.deviceDecision: 'deviceDecision',
};

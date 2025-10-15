import 'package:at_auth/at_auth.dart' show AtKeys;

class AtClientData {
  AtClientDataConfig? config;
  List<AtKeys> keys;
  String? defaultAtsign;

  AtClientData({
    this.config,
    this.keys = const [],
    this.defaultAtsign,
  });

  AtClientData copyWith({
    AtClientDataConfig? config,
    List<AtKeys>? keys,
    String? defaultAtsign,
  }) {
    return AtClientData(
      config: config ?? this.config,
      keys: keys ?? this.keys,
      defaultAtsign: defaultAtsign ?? this.defaultAtsign,
    );
  }

  factory AtClientData.fromJson(Map<String, dynamic> json) => AtClientData(
        config: json['config'] == null ? null : AtClientDataConfig.fromJson(json['config'] as Map<String, dynamic>),
        keys:
            (json['keys'] as List<dynamic>?)?.map((e) => AtKeys.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        defaultAtsign: json['defaultAtsign'],
      );

  Map<String, dynamic> toJson() => {
        'config': config,
        'keys': keys,
        'defaultAtsign': defaultAtsign,
      };
}

class AtClientDataConfig {
  final int? schemaVersion;
  final bool? useSharedStorage; //Share atsign account between apps

  const AtClientDataConfig({
    this.schemaVersion,
    this.useSharedStorage,
  });

  factory AtClientDataConfig.defaultConfig() => AtClientDataConfig();

  factory AtClientDataConfig.fromJson(Map<String, dynamic> json) => AtClientDataConfig(
        schemaVersion: json['schemaVersion'] is int ? json['schemaVersion'] : null,
        useSharedStorage: json['useSharedAtsign'] is bool ? json['useSharedAtsign'] : null,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'useSharedAtsign': useSharedStorage,
      };

  AtClientDataConfig copyWith({
    int? schemaVersion,
    bool? useSharedStorage,
  }) {
    return AtClientDataConfig(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      useSharedStorage: useSharedStorage ?? this.useSharedStorage,
    );
  }
}

bool isNotEmptyOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return false;
  return value.isNotEmpty;
}

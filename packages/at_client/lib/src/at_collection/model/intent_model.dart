class IntentModel {
  late String uid;
  late String dataKeyIdentifier;
  late IntentOperation intentOperation;
  late DateTime timestamp;

  IntentModel(this.uid, this.dataKeyIdentifier, 
      this.intentOperation, this.timestamp);

  IntentModel.fromJson(Map json) {
    uid = json['uid'];
    dataKeyIdentifier = json['dataKeyIdentifier'];
    intentOperation = IntentOperation.values.byName(json['intentOperation']);
    timestamp = DateTime.parse(json['timestamp'].toString());
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['uid'] = uid;
    data['dataKeyIdentifier'] = dataKeyIdentifier;
    data['intentOperation'] = intentOperation.name;
    data['timestamp'] = timestamp.toString();
    return data;
  }
}

class IntentUpdateModel extends IntentModel {
  late String value;

  IntentUpdateModel(
    this.value,
    uid, dataKeyIdentifier, timestamp
  ) : super(uid, dataKeyIdentifier, IntentOperation.UPDATE, timestamp);
  
  IntentUpdateModel.fromJson(Map json)
      : super(
          json['uid'],
          json['dataKeyIdentifier'],
          IntentOperation.values.byName(json['intentOperation']),
          DateTime.parse(json['timestamp'].toString()),
        ) {
    value = json['value'];
  }

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['value'] = value;
    data['uid'] = uid;
    data['dataKeyIdentifier'] = dataKeyIdentifier;
    data['intentOperation'] = intentOperation.name;
    data['timestamp'] = timestamp.toString();
    return data;
  }
}

class IntentShareModel extends IntentModel {
  late List<String> atsigns;

  IntentShareModel(
    this.atsigns,
    uid, dataKeyIdentifier, timestamp
  ) : super(uid, dataKeyIdentifier, IntentOperation.SHARE, timestamp);
  
  IntentShareModel.fromJson(Map json)
      : super(
          json['uid'],
          json['dataKeyIdentifier'],
          IntentOperation.values.byName(json['intentOperation']),
          DateTime.parse(json['timestamp'].toString()),
        ) {
    atsigns = json['atsigns'].cast<String>();
  }

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['atsigns'] = atsigns;
    data['uid'] = uid;
    data['dataKeyIdentifier'] = dataKeyIdentifier;
    data['intentOperation'] = intentOperation.name;
    data['timestamp'] = timestamp.toString();
    return data;
  }
}

class IntentDeleteModel extends IntentModel {

  IntentDeleteModel(
    uid, dataKeyIdentifier, timestamp
  ) : super(uid, dataKeyIdentifier, IntentOperation.DELETE, timestamp);
  
  IntentDeleteModel.fromJson(Map json)
      : super(
          json['uid'],
          json['dataKeyIdentifier'],
          IntentOperation.values.byName(json['intentOperation']),
          DateTime.parse(json['timestamp'].toString()),
        );

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['uid'] = uid;
    data['dataKeyIdentifier'] = dataKeyIdentifier;
    data['intentOperation'] = intentOperation.name;
    data['timestamp'] = timestamp.toString();
    return data;
  }
}

enum IntentOperation { 
  UPDATE, 
  SHARE, 
  DELETE 
}
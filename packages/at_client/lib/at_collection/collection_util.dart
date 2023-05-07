class CollectionUtil {
  /// replaces character with '-' if it's not alphanumeric.
  static String format(String id) {
    String formattedId = id;

    formattedId = formattedId.trim().toLowerCase();
    formattedId = formattedId.replaceAll(' ', '-');

    for (int i = 0; i < formattedId.length; i++) {
      if (RegExp(r'^(?!\s*$)[a-zA-Z0-9-_]{1,20}$').hasMatch(formattedId[i]) ==
          false) {
        formattedId = formattedId.replaceAll(formattedId[i], '-');
      }
    }

    return formattedId;
  }

  /// throws exception if id or collectionName is empty
  static void checkForNullOrEmptyValues(
    String? id,
    String? collectionName,
      String? namespace,
  ) {
    if (id == null || id.isEmpty) {
      throw Exception('id cannot be null or empty');
    }

    if (collectionName == null || collectionName.isEmpty) {
      throw Exception('collectionName cannot be null or empty');
    }

    if (namespace == null || namespace.isEmpty) {
      throw Exception('namespace cannot be null or empty');
    }
  }

  /// Throws exception if id or collectionName is not added.
  static void validateModel({
    required Map<String, dynamic> modelJson,
    required String id,
    required String collectionName,
    required String namespace
  }) {
    checkForNullOrEmptyValues(id, collectionName, namespace);

    if (modelJson['id'] == null) {
      throw Exception('id not added in toJson');
    }

    if (modelJson['collectionName'] == null) {
      throw Exception('collectionName not added in toJson');
    }


  }

  /// adds id and collectionName fields in [objectJson]
  static Map<String, dynamic> initAndValidateJson({
    required Map<String, dynamic> collectionModelJson,
    required String id,
    required String collectionName,
    required String namespace,
  }) {
    collectionModelJson['id'] = id;
    collectionModelJson['collectionName'] = collectionName;
    CollectionUtil.validateModel(
      modelJson: collectionModelJson,
      id: id,
      collectionName: collectionName,
      namespace: namespace
    );
    return collectionModelJson;
  }

  static String makeRegex({String? formattedId, String? collectionName, String? namespace}) {
    String regex = formattedId ?? '';

    if (collectionName != null) {
      regex = "$regex.$collectionName";
    } else {
      regex = '$regex.*';
    }

    regex = '$regex.atcollectionmodel';

    if(namespace != null) {
      regex = '$regex.$namespace';
    }

    return regex;
  }

  static String getNamespaceFromKey(String atKey) {
    return atKey.substring(atKey.indexOf("atcollectionmodel.") + "atcollectionmodel.".length, atKey.lastIndexOf('@'));

  }
}

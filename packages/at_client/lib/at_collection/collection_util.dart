class CollectionUtil {
  /// replaces character with '-' if it's not alphanumeric.
  static String format(String id) {
    String formattedId = id;

    formattedId = formattedId.trim().toLowerCase();
    formattedId = formattedId.replaceAll(' ', '-');

    for (int i = 0; i < formattedId.length; i++) {
      if (RegExp(r'^(?!\s*$)[a-zA-Z0-9- ]{1,20}$').hasMatch(formattedId[i]) ==
          false) {
        formattedId = formattedId.replaceAll(formattedId[i], '-');
      }
    }

    return formattedId;
  }

  /// throws exception if id or collectionName is empty
  static void validateIdAndCollectionName(
    String? id,
    String? collectionName,
  ) {
    if (id == null || id.trim().isEmpty) {
      throw Exception('id not found');
    }

    if (collectionName == null || collectionName.trim().isEmpty) {
      throw Exception('collectionName not found');
    }
  }

  /// Throws exception if id or collectionName is not added.
  static void validateModel({
    required Map<String, dynamic> modelJson,
    required String id,
    required String collectionName,
  }) {
    validateIdAndCollectionName(id, collectionName);

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
  }) {
    collectionModelJson['id'] = id;
    collectionModelJson['collectionName'] = collectionName;
    CollectionUtil.validateModel(
      modelJson: collectionModelJson,
      id: id,
      collectionName: collectionName,
    );
    return collectionModelJson;
  }

  static String makeRegex({String? formattedId, String? collectionName}) {
    String regex = formattedId ?? '';

    if (collectionName != null) {
      regex = "$regex.$collectionName";
    } else {
      regex = '$regex.*';
    }

    // regex = '$regex.atcollectionmodel';
    return regex;
  }
}

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

  /// Throws exception if id or collectionName is not added.
  static void validateModel({
    required Map<String, dynamic> modelJson,
    required String id,
    required String collectionName,
  }) {
    if (id.trim().isEmpty) {
      throw Exception('id not found');
    }

    if (collectionName.trim().isEmpty) {
      throw Exception('collectionName not found');
    }

    if (modelJson['id'] == null) {
      throw Exception('id not added in toJson');
    }

    if (modelJson['collectionName'] == null) {
      throw Exception('collectionName not added in toJson');
    }
  }
}

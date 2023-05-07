import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_utils.dart';
import 'package:uuid/uuid.dart';
import 'at_json_collection_model.dart';
import 'collections.dart';
import 'impl/at_collection_operations_impl.dart';
import 'impl/at_collection_query_operations_impl.dart';
import 'impl/at_collection_stream_operations_impl.dart';

abstract class AtCollectionModel<T> implements AtCollectionModelOperations {
  final _logger = AtSignLogger('AtCollectionModel');
  /// [id] uniquely identifies this model.
  ///
  /// By default, id is set to UUID.
  String id = Uuid().v4();
  /// [collectionName] is used to identify collections of same type
  /// For example, if Preference is a class that extends AtCollectionModel then collectionName can be "preferences"
  /// Defaulted to the name of the dart class in lowercase
  late String collectionName;
  /// namespace is used to persist the collection model
  /// Typically namespace is used to identify the app that is used to persist the data.
  late String namespace;
  late AtCollectionModelOperations _atCollectionModelOperations;
  late AtCollectionModelStreamOperationsImpl streams;

  static final AtJsonCollectionModelFactory _jsonCollectionModelFactory =
      AtJsonCollectionModelFactory();
  static final AtCollectionQueryOperations _atCollectionQueryOperations =
      AtCollectionQueryOperationsImpl();


  AtCollectionModel() {
    _atCollectionModelOperations = AtCollectionModelOperationsImpl(this);
    streams = AtCollectionModelStreamOperationsImpl(this);
    // Default the collectionName to the name of the class extending AtCollectionModel
    collectionName = runtimeType.toString().toLowerCase();
  }

  /// Registers list of AtCollectionModelFactory instances.
  /// These factories will be used while creating specific sub classes of [AtCollectionModel] for a given collection
  static registerFactories(List<AtCollectionModelFactory> factories) {
    for(var atCollectionModelFactory in factories) {
      AtCollectionModelFactoryManager.getInstance()
          .register(atCollectionModelFactory);
    }
  }

  /// Returns an instance of a class extending  [AtCollectionModel] for the given [id], [namespace] and [collectionName]
  /// An instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  ///
  /// Throws [Exception] when an AtCollectionModel could not found for the given inputs
  static Future<T> getModel<T extends AtCollectionModel>(
      {required String id,
      required String namespace,
      required String collectionName}) async {
    AtCollectionModelFactoryManager.getInstance()
        .register(_jsonCollectionModelFactory);
    return _atCollectionQueryOperations.getModel(
        id, namespace, collectionName);
  }

  /// Returns list of AtCollectionModels that are created for the [collectionName] passed
  /// Returns an empty list when there are no matches
  ///
  /// An instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  static Future<List<T>> getModelsByCollectionName<T extends AtCollectionModel>(
      String collectionName) async {
    AtCollectionModelFactoryManager.getInstance()
        .register(_jsonCollectionModelFactory);
    return _atCollectionQueryOperations
        .getModelsByCollectionName(collectionName);
  }

  /// Returns list of AtCollectionModels that are shared with the given [atSign]
  /// Returns an empty list when nothing has been shared
  ///
  /// Instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  static Future<List<T>>
      getModelsSharedWith<T extends AtCollectionModel>(String atSign) async {
    AtCollectionModelFactoryManager.getInstance()
        .register(_jsonCollectionModelFactory);
    AtUtils.formatAtSign(atSign)!;
    return _atCollectionQueryOperations.getModelsSharedWith(atSign);
  }

  /// Returns list of AtCollectionModels that are shared by the given [atSign]
  /// Returns an empty list when nothing has been shared
  ///
  /// Instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  static Future<List<T>> getModelsSharedBy<T extends AtCollectionModel>(
      String atSign) async {
    AtCollectionModelFactoryManager.getInstance()
        .register(_jsonCollectionModelFactory);
    AtUtils.formatAtSign(atSign)!;
    return _atCollectionQueryOperations.getModelsSharedBy(atSign);
  }

  @override
  Future<bool> save(
      {bool share = true, ObjectLifeCycleOptions? options}) async {
    return _atCollectionModelOperations.save(share: share, options: options);
  }

  @override
  Future<List<String>> getSharedWith() async {
    return _atCollectionModelOperations.getSharedWith();
  }

  @override
  Future<bool> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options}) async {
    return _atCollectionModelOperations.share(atSigns, options: options);
  }

  @override
  Future<bool> delete() async {
    return _atCollectionModelOperations.delete();
  }

  @override
  Future<bool> unshare({List<String>? atSigns}) async {
    return _atCollectionModelOperations.unshare(atSigns: atSigns);
  }
}

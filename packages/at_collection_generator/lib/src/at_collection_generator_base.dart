import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:at_collection_annotation/at_collection_annotation.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:source_gen/source_gen.dart';

class AtCollectionGenerator extends GeneratorForAnnotation<AtCollectionAnnotation> {
  @override
  FutureOr<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    return _generateWidgetSource(element);
  }

  String _generateWidgetSource(Element element) {
    final visitor = ModelVisitor();
    element.visitChildren(visitor);
    final sourceBuilder = StringBuffer();
    var className = "${visitor.className}Collection";

    // /// imports
    sourceBuilder.writeln("import 'dart:convert';");
    sourceBuilder.writeln("import 'package:at_client/at_collection/at_collection_model.dart';");
    sourceBuilder.writeln("import 'package:at_client/at_collection/model/spec/at_collection_model_spec.dart';");

    /// Class name
    sourceBuilder.writeln("class $className extends AtCollectionModel{");

    /// declare varibales
    final variablesBuilder = StringBuffer();
    for (String parameterName in visitor.fields.keys) {
      variablesBuilder.writeln("${(visitor.fields[parameterName]).toString().replaceAll('*', '')} $parameterName;"); 
    }
    sourceBuilder.write(variablesBuilder);
    
    /// empty space
    sourceBuilder.writeln("");

    //// Constructor
    sourceBuilder.write("$className (");
    final parametersBuilder = StringBuffer();
    for (String parameterName in visitor.fields.keys) {
      parametersBuilder.write("this.$parameterName,"); 
    }
    sourceBuilder.write(parametersBuilder);
    sourceBuilder.writeln("):super(");
    sourceBuilder.writeln("collectionName: \"${visitor.className}\",");
    sourceBuilder.writeln(");");

    /// empty space
    sourceBuilder.writeln("");

    /// static methods
    sourceBuilder.writeln("static Future<List<$className>> getAllData() async {");
        sourceBuilder.writeln("return (await AtCollectionModel.getAll<$className>());");
    sourceBuilder.writeln("}");

    sourceBuilder.writeln("static Future<$className> getById(String keyId) async {");
        sourceBuilder.writeln("return (await AtCollectionModel.load<$className>(keyId));");
    sourceBuilder.writeln("}");

    /// fromJson method
    sourceBuilder.writeln("@override");
    sourceBuilder.writeln("$className fromJson(String jsonDecodedData)");
    sourceBuilder.writeln("{");
    sourceBuilder.writeln("var json = jsonDecode(jsonDecodedData);");
    /// we need to create an object of this class and return from here
    sourceBuilder.writeln("var newModel = $className(");
      /// populate all the members
      for (String parameterName in visitor.fields.keys) {
        var type = (visitor.fields[parameterName]).toString().replaceAll('*', '');
        /// TODO: We should use named parameters here for easier use
        if(type == "String"){
          sourceBuilder.write("json['$parameterName'],"); 
        } else if (type == "bool"){
          sourceBuilder.write("json['result'] == 'true',"); 
        } else {
          sourceBuilder.write("$type.parse(json['$parameterName']),"); 
        }
      }
    sourceBuilder.writeln(");");
    sourceBuilder.writeln("newModel.id = json['id'];");
    sourceBuilder.writeln("return newModel;");
    sourceBuilder.writeln("}");

    /// toJson method
    sourceBuilder.writeln("@override");
    sourceBuilder.writeln("Map<String, dynamic> toJson()");
    sourceBuilder.writeln("{");
    sourceBuilder.writeln("final Map<String, dynamic> data = {};");
    sourceBuilder.writeln("data['id'] = id;");
    sourceBuilder.writeln("data['collectionName'] = AtCollectionModelSpec.collectionName;");
    /// populate all the members
      for (String parameterName in visitor.fields.keys) {
        var type = (visitor.fields[parameterName]).toString().replaceAll('*', '');
        /// TODO: We should use named parameters here for easier use
        if(type == "String"){
          sourceBuilder.write("data['$parameterName'] = $parameterName;"); 
        } else {
          sourceBuilder.write("data['$parameterName'] = $parameterName.toString();"); 
        }
      }
    sourceBuilder.writeln("return data;");
    sourceBuilder.writeln("}");

    sourceBuilder.writeln("}");
    return sourceBuilder.toString();
  }
}

class ModelVisitor extends SimpleElementVisitor {
  late String className;
  Map<String, DartType> fields = Map();

  @override
  visitConstructorElement(ConstructorElement element) {
    className = element.displayName;
    return super.visitConstructorElement(element);
  }

  @override
  visitFieldElement(FieldElement element) {
    fields[element.name] = element.type;

    return super.visitFieldElement(element);
  }
}

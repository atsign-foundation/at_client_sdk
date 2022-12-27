### A generator package to help you generate classes that extends AtCollectionModel 
### to provide with all at_sdk functionalities

# Steps to use:
1. Create a model class, eg: user.dart
2. Define you structure of the model class,
    ```
        class User {
            final String name;
            final String login;
            final int number;

            User(this.name, this.login, this.number);
        }
    ```
3. Annotate the model class with @at_collection_class
4. Create a new class with name `<model_class_file>.g.dart`, append .g.dart to the name of the original model class
5. Add these imports in the original model class
    ```
        import 'dart:convert';
        import 'package:at_client/at_client.dart';
        import 'package:at_client/at_collection/at_collection_model.dart';

        import 'package:at_collection_annotation/at_collection_annotation.dart';
    ```
6. Also add `part <model_class_file>.g.dart;` in the model class
7. And add `part of 'user.dart';` in the `<model_class_file>.g.dart`, class
8. Now run `flutter packages pub run build_runner build --delete-conflicting-outputs`
        to generate the new classes
9. Make sure to have `build_runner` and `at_collection_generator` in the dependencies
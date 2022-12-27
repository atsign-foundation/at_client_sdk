### A generator package to help you generate classes that extends AtCollectionModel to provide with all at_sdk functionalities

# Steps to use:
1. Create a model class, eg: user.dart
2. Define you structure of the model class, 
    eg: 
    ```
        class User {
            final String name;
            final String login;
            final int number;

            User(this.name, this.login, this.number);
        }
    ```
3. Annotate the model class with `@at_collection_class`,
    eg:
    ```
     @at_collection_class   
     class User {
        ...
     }
    ```
4. Add `build_runner: "2.3.3"` and `at_collection_generator: <path or version>` to your pubspec.yaml
5. Now run `flutter packages pub run build_runner build --delete-conflicting-outputs` in the root of your project to generate the new at_collection classes
6. The new generated at_collection class should have all the desired at_sdk functionalities
import 'dart:async';
import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_common_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';

final StreamController<ThemeMode> updateThemeMode = StreamController<ThemeMode>.broadcast();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ThemeMode>(
      stream: updateThemeMode.stream,
      initialData: ThemeMode.light,
      builder: (context, snapshot) {
        return MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFFf04924),
            colorScheme: ThemeData.light().colorScheme.copyWith(surface: Colors.white),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'RobotoSlab',
            primaryColor: const Color(0xFFF05E3E),
            colorScheme: ThemeData.dark().colorScheme.copyWith(surface: Colors.black),
          ),
          themeMode: snapshot.data,
          title: 'Example App',
          home: const MyHomePage(title: 'Example App Home Page'),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String? title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    SizeConfig().init(context);
    return Scaffold(
      appBar: CustomAppBar(
        appBarColor: Theme.of(context).primaryColor,
        showBackButton: false,
        showTitle: true,
        titleText: widget.title,
        titleTextStyle: CustomTextStyles.primaryBold18.copyWith(
          color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
        ),
        showLeadingIcon: true,
        leadingIcon: Icon(
          Icons.home_outlined,
          color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
        ),
        onTrailingIconPressed: () {
          log('Trailing icon of appbar pressed');
        },
        showTrailingIcon: true,
        trailingIcon: Center(
          child: IconButton(
            onPressed: () {
              updateThemeMode.sink
                  .add(Theme.of(context).brightness == Brightness.light ? ThemeMode.dark : ThemeMode.light);
            },
            icon: Icon(
              Theme.of(context).brightness == Brightness.light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 20.0),
            const Text('Custom AppBar ☝️'),
            const Divider(
              color: Color(0xFFBEC0C8),
              height: 30,
              thickness: 2,
            ),
            const Text('Custom Input field:'),
            CustomInputField(
              icon: Icons.emoji_emotions_outlined,
              width: 200.0,
              initialValue: "initial value",
              value: (String val) {
                log('Current value of input field: $val');
              },
              inputFieldColor: Theme.of(context).brightness == Brightness.light
                  ? Colors.black.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.2),
            ),
            const Divider(
              color: Color(0xFFBEC0C8),
              height: 30,
              thickness: 2,
            ),
            const Text('Custom Button:'),
            CustomButton(
              height: 50.0,
              width: 200.0,
              buttonText: 'Add',
              onPressed: () {
                log('Custom button pressed');
              },
              buttonColor: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
              fontColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.black,
            ),
          ],
        ),
      ),
    );
  }
}

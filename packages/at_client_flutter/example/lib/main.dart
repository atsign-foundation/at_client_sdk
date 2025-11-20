import 'package:flutter/material.dart';
import 'package:at_client_flutter/src/widgets/shared/atsign_rootdomain_dialog.dart';
import 'package:at_client_flutter/src/widgets/registrar_cram_dialog.dart';
import 'package:at_auth/at_auth.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  AtOnboardingRequest? _onboardingRequest;
  AtOnboardingResponse? _onboardingResponse;

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[ 
            ElevatedButton(onPressed: () => RegistrarCramDialog.onboard(context,
              "my.atsign.com",
              "055fe540-65d9-46b2-bac3-5d20af4ef115",
              onSubmit: (AtOnboardingRequest req, String cramKey) {
                setState(() {
                  _onboardingRequest = req;

                });
              },
              ), child: const Text("Show OTP Dialog")),
          ]
        ),
      ),
    );
  }
}

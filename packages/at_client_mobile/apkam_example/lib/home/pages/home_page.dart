import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  late final service = AuthorisationService()..init();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(
                        title: const Text('Authorisation Home Page'),
                      ),
                      body: Padding(
                        padding: const EdgeInsets.all(64.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: AuthorisationHub(
                            service: service,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Authorisation Home Page'),
            ),
          ],
        ),
      ),
    );
  }
}

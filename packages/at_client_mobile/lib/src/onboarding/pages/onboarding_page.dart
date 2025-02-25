import 'package:at_client_mobile/src/onboarding/pages/register_page.dart';
import 'package:flutter/material.dart';

enum _OnboardingPageType { init, login, register }

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  OnboardingPageState createState() => OnboardingPageState();
}

class OnboardingPageState extends State<OnboardingPage> {
  late _OnboardingPageType _type;

  @override
  void initState() {
    super.initState();
    _type = _OnboardingPageType.init;
  }

  @override
  Widget build(BuildContext context) {
    switch (_type) {
      case _OnboardingPageType.init:
        return Row(
          children: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _type = _OnboardingPageType.login;
                });
              },
              child: Text('Login'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _type = _OnboardingPageType.register;
                });
              },
              child: Text('Register'),
            ),
          ],
        );
      case _OnboardingPageType.login:
        return Text('Login Page');
      case _OnboardingPageType.register:
        return RegisterPage(
          onCramKeyReceived: (cramKey) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cram Key Received: $cramKey')),
            );
            setState(() {
              _type = _OnboardingPageType.login;
            });
          },
        );
    }
  }
}

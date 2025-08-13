import 'package:at_app_flutter/at_app_flutter.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_invitation_flutter/at_invitation_flutter.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';
import 'package:uni_links/uni_links.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'constants.dart';

class SecondScreen extends StatefulWidget {
  const SecondScreen({Key? key}) : super(key: key);

  @override
  State<SecondScreen> createState() => _SecondScreenState();
}

class _SecondScreenState extends State<SecondScreen> {
  final AtSignLogger _logger = AtSignLogger('Second Screen');
  String activeAtSign = '';
  GlobalKey<NavigatorState> scaffoldKey = GlobalKey();
  String chatWithAtSign = '';
  bool showOptions = false;

  // for group chat
  String groupId = '';
  String member1 = '';
  String member2 = '';

  /// Get the AtClientManager instance
  var atClientManager = AtClientManager.getInstance();

  @override
  void initState() {
    initializeInvitationWidget();
    scaffoldKey = GlobalKey<NavigatorState>();
    _handleIncomingLinks();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Second Screen')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              height: 20.0,
            ),
            Container(
              padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
              child: Text(
                'Welcome $activeAtSign!',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(
              height: 20.0,
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                  'Use this button to invite any of your contacts to this app using their email or phone number'),
            ),
            const SizedBox(
              height: 10.0,
            ),
            TextButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all<Color>(Colors.black12),
              ),
              onPressed: () {
                shareAndInvite(context, 'welcome');
              },
              child: const Text(
                'Share with a friend',
                style: TextStyle(color: Colors.black),
              ),
            ),
            const SizedBox(
              height: 10.0,
            ),
            TextButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all<Color>(Colors.black12),
              ),
              onPressed: () {
                _checkForInvite();
              },
              child: const Text(
                'Check for invite',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void initializeInvitationWidget() async {
    var currentAtSign = atClientManager.atClient.getCurrentAtSign();
    setState(() {
      activeAtSign = currentAtSign ?? '';
    });
    initializeInvitationService(
        navkey: scaffoldKey,
        webPage: MixedConstants.cookiePage,
        rootDomain: AtEnv.rootDomain);
  }

  void _checkForInvite() async {
    String url = MixedConstants.cookiePage;
    await canLaunchUrlString(url)
        ? await launchUrlString(url)
        : throw 'Could not launch $url';
  }

  void _handleIncomingLinks() {
    // It will handle app links while the app is already started - be it in
    // the foreground or in the background.
    uriLinkStream.listen((Uri? uri) {
      if (mounted) {
        if (uri != null) {
          var queryParameters = uri.queryParameters;
          fetchInviteData(context, queryParameters['key'] ?? '',
              queryParameters['atsign'] ?? '');
        }
      }
    }, onError: (Object err) {
      _logger.severe('Error in incoming links: ${err.toString()}');
    });
  }
}

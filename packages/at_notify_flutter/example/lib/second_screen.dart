import 'package:at_app_flutter/at_app_flutter.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_notify_flutter/screens/notify_screen.dart';
import 'package:at_notify_flutter/services/notify_service.dart';
import 'package:at_notify_flutter/utils/init_notify_service.dart';
import 'package:at_notify_flutter/utils/notify_utils.dart';
import 'package:flutter/material.dart';

import 'main.dart';

//* The next screen after onboarding (second screen)
class SecondScreen extends StatefulWidget {
  const SecondScreen({Key? key}) : super(key: key);

  @override
  State<SecondScreen> createState() => _SecondScreenState();
}

class _SecondScreenState extends State<SecondScreen> {
  GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  String? activeAtSign;
  var atClientManager = AtClientManager.getInstance();
  AtClientPreference atClientPreference = AtClientPreference();
  TextEditingController atSignController = TextEditingController(text: '');
  TextEditingController messageController = TextEditingController(text: '');

  @override
  void initState() {
    getAtSignAndInitializeNotify();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        title: const Text('Notify Example'),
      ),
      body: Builder(
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome $activeAtSign',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(
                  height: 16.0,
                ),
                TextField(
                  controller: atSignController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '@atSign'),
                  onChanged: (text) {},
                ),
                const SizedBox(
                  height: 8.0,
                ),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter Message'),
                  onChanged: (text) {},
                ),
                const SizedBox(
                  height: 16.0,
                ),
                TextButton(
                  onPressed: _sendMessage,
                  child: const Text(
                    'Notify Text',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => NotifyScreen(notifyService: NotifyService())),
                    );
                  },
                  child: const Text(
                    'Get past notifications',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _sendMessage() async {
    if (atSignController.text.isEmpty) {
      showSnackBar('Enter atsign');
      return;
    }

    if (messageController.text.isEmpty) {
      showSnackBar('Enter message');
      return;
    }

    var isValidAtsign = await checkAtsign();
    if (!isValidAtsign) {
      showSnackBar('Atsign not valid');
      return;
    }
    if (!mounted) return showSnackBar('Something went wrong');
    var res = await notifyText(
      context,
      activeAtSign,
      atSignController.text,
      messageController.text,
    );
    if (res) {
      messageController.clear();
      showSnackBar('Message sent succesfully', color: Colors.green);
    } else {
      showSnackBar('Something went wrong');
    }
  }

  Future<bool> checkAtsign() async {
    if (atSignController.text.isEmpty) {
      return false;
    } else if (!atSignController.text.contains('@')) {
      atSignController.text = '@${atSignController.text}';
    }
    // ignore: deprecated_member_use
    var checkPresence = await AtLookupImpl.findSecondary(atSignController.text, AtEnv.rootDomain, 64);
    return checkPresence != null;
  }

  void getAtSignAndInitializeNotify() async {
    var currentAtSign = atClientManager.atClient.getCurrentAtSign();
    setState(() {
      activeAtSign = currentAtSign;
    });

    atClientPreference = await loadAtClientPreference();

    initializeNotifyService(
      atClientManager,
      activeAtSign!,
      atClientPreference,
      rootDomain: AtEnv.rootDomain,
    );
  }

  showSnackBar(String text, {Color color = Colors.red}) {
    ScaffoldMessenger.of(scaffoldKey.currentContext!).showSnackBar(SnackBar(
      backgroundColor: color,
      dismissDirection: DismissDirection.horizontal,
      content: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          letterSpacing: 0.1,
          fontWeight: FontWeight.normal,
        ),
      ),
    ));
  }
}

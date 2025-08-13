import 'package:at_sync_ui_flutter/at_sync_ui.dart';
import 'package:at_sync_ui_flutter/at_sync_ui_flutter.dart';
import 'package:at_sync_ui_flutter_example/custom_sync_widget.dart';
import 'package:at_sync_ui_flutter_example/ui_options.dart';
import 'package:flutter/material.dart';

import 'main.dart';

class SecondScreen extends StatefulWidget {
  final String activeAtSign;

  const SecondScreen({required this.activeAtSign, Key? key}) : super(key: key);

  @override
  State<SecondScreen> createState() => _SecondScreenState();
}

class _SecondScreenState extends State<SecondScreen> {
  late String activeAtSign;

  @override
  void initState() {
    try {
      super.initState();
      activeAtSign = widget.activeAtSign;
      AtSyncUIService().init(
        appNavigator: NavService.navKey,
        onSuccessCallback: _onSuccessCallback,
        onErrorCallback: _onErrorCallback,
        showRemoveAtsignOption: true,
        onAtSignRemoved: _onAtSignRemoved,
      );
    } catch (e) {
      //
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  _onSuccessCallback(syncStatus) {
    showSnackBar('Sync successful');
  }

  _onErrorCallback(syncStatus) {
    showSnackBar('Sync not successful', isError: true);
  }

  _onAtSignRemoved() {
    showSnackBar('atSign removed from keychain', isError: false);

    /// add condition to switch to next atSign or display appropriate message
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Second Screen'),
      ),
      body: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
              child: Text(
                'Welcome $activeAtSign!',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // ignore: deprecated_member_use
                AtSyncUIService().sync();
              },
              child: const Text('Default Sync'),
            ),
            ElevatedButton(
              onPressed: () async {
                // ignore: deprecated_member_use
                AtSyncUIService().sync(
                  atSyncUIOverlay: AtSyncUIOverlay.dialog,
                );
              },
              child: const Text('Sync with dialog overlay'),
            ),
            ElevatedButton(
              onPressed: () async {
                // ignore: deprecated_member_use
                AtSyncUIService().sync(
                  atSyncUIOverlay: AtSyncUIOverlay.snackbar,
                );
              },
              child: const Text('Sync with snackbar'),
            ),
            ElevatedButton(
              onPressed: () async {
                // ignore: deprecated_member_use
                AtSyncUIService().sync(
                  atSyncUIOverlay: AtSyncUIOverlay.none,
                );
              },
              child: const Text('Sync with no UI'),
            ),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const UIOptions()));
              },
              child: const Text('See all UI options'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Current State: '),
                StreamBuilder<AtSyncUIStatus>(
                  stream: AtSyncUIService().atSyncUIListener,
                  builder: ((context, snapshot) => CustomSyncIndicator(
                        uiStatus: snapshot.data ?? AtSyncUIStatus.notStarted,
                        size: 50,
                        child: const ClipOval(
                          child: Image(
                            height: 50,
                            width: 50,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            image: NetworkImage('https://picsum.photos/200/300'),
                          ),
                        ),
                      )),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // ignore: deprecated_member_use
          AtSyncUIService().sync(
            atSyncUIOverlay: AtSyncUIOverlay.none,
          );
        },
        child: const Icon(Icons.sync),
      ),
    );
  }

  Widget alertDialogContent() {
    return AlertDialog(
      title: const Text('you are not authenticated.'),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
          child: const Text(
            'Ok',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }

  void showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(NavService.navKey.currentContext!).showSnackBar(SnackBar(
      backgroundColor: isError ? const Color(0xFFe34040) : Colors.green,
      content: Text(
        msg,
        style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 0.1, fontWeight: FontWeight.normal),
      ),
    ));
  }
}

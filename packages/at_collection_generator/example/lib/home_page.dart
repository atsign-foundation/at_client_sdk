import 'package:example/models/event.g.dart';
import 'package:example/models/user.g.dart';
import 'package:flutter/material.dart';

class MyHomePage extends StatefulWidget {
  MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var userCollection = UserCollection('name', 'login', 1, 'address');
  var eventCollection = EventCollection('New year party', 'Church Street', 25, false, 930.50);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("At collection generator demo"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextButton(onPressed: () async {
              var _saveRes = await eventCollection.save();
              showScaffold(_saveRes.toString());
            }, 
              child: const Text("Save"),
            ),
            TextButton(onPressed: () async {
              var _saveRes = await eventCollection.shareWith(['@colin', '@k']);
              showScaffold(_saveRes.toString());
            }, 
              child: const Text("Share"),
            ),
            TextButton(onPressed: () async {
              var _saveRes = await eventCollection.unshare(atSigns: ['@colin']);
              showScaffold(_saveRes.toString());
            }, 
              child: const Text("UnShare"),
            ),
            TextButton(onPressed: () async {
              var _saveRes = await eventCollection.getSharedWith();
              showScaffold(_saveRes.toString());
            }, 
              child: const Text("getSharedWith"),
            ),
            TextButton(onPressed: () async {
              var _saveRes = await EventCollection.getById(eventCollection.id);
              showScaffold('${_saveRes.title}, ${_saveRes.noOfPeople}, ${_saveRes.cancelled},');
            }, 
              child: const Text("get element"),
            ),
          ],
        ),
      ),
    );
  }

  void showScaffold(String msg){
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
      backgroundColor: Colors.red,
      content: Text(
        msg,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            letterSpacing: 0.1,
            fontWeight: FontWeight.normal),
      ),
    ));
  }
}
import 'package:demo/src/services/sdk.service.dart';
import 'package:flutter/material.dart';
import 'package:at_commons/at_commons.dart';

class HomeScreen extends StatefulWidget {
  static const String id = 'HomeScreen';
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Set of strings
  Set<String> _selectedStrings = <String>{};
  final ClientSdkService _clientSdkService = ClientSdkService.getInstance();
  String? atSign,
      _key,
      _deleteKey,
      _value,
      _lookupKey,
      _lookupValue,
      notifyAtSign;
  List<String?> _scanItems = <String?>[];
  bool _isUpdateLoading = false,
      _isScanLoading = false,
      _isLookupLoading = false,
      _isDeleteLoading = false;
  final TextEditingController? _lookupTextFieldController =
          TextEditingController(),
      _keyTextFieldController = TextEditingController(),
      _valueTextFieldController = TextEditingController();

  @override
  void initState() {
    Future.microtask(() async {
      atSign = await _clientSdkService.getAtSign();
      setState(() {});
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Welcome ${atSign ?? 'to dashboard'}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _clientSdkService.logout(context),
            icon: const Icon(
              Icons.logout,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              color: Colors.white,
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18.0),
                child: Column(
                  children: [
                    ListTile(
                      title: const Text(
                        'Update ',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 20.0,
                        ),
                      ),
                      subtitle: ListView(
                        shrinkWrap: true,
                        children: <Widget>[
                          TextField(
                            controller: _keyTextFieldController,
                            decoration:
                                const InputDecoration(hintText: 'Enter Key'),
                            onChanged: (String key) {
                              _key = key;
                            },
                          ),
                          TextField(
                            controller: _valueTextFieldController,
                            decoration: const InputDecoration(
                              hintText: 'Enter Value',
                            ),
                            onChanged: (String value) {
                              _value = value;
                            },
                          ),
                        ],
                      ),
                    ),
                    _isUpdateLoading
                        ? const Loading()
                        : Container(
                            width: 150,
                            margin: const EdgeInsets.all(10),
                            child: TextButton(
                              child: const Text(
                                'Update',
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                              ),
                              onPressed: () async {
                                setState(() => _isUpdateLoading = true);
                                if (_key != null && _value != null) {
                                  AtKey pair = AtKey()
                                    ..key = _key
                                    ..sharedWith = atSign;
                                  bool _put = await _clientSdkService.put(
                                      pair, _value!);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${pair.key} value ${_put ? 'updated' : 'not updated'}',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                }
                                setState(() => _isUpdateLoading = false);
                              },
                            ),
                          ),
                  ],
                ),
              ),
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              color: Colors.white,
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListTile(
                      title: const Text(
                        'Scan',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 20.0,
                        ),
                      ),
                      subtitle: DropdownButton<String>(
                        hint: const Text('Select Key'),
                        items: _scanItems.map((String? key) {
                          return DropdownMenuItem<String>(
                            value: key,
                            child: Text(key!),
                          );
                        }).toList(),
                        onChanged: (String? value) {
                          if(value != null){
                            _selectedStrings.add(value);
                          }
                          setState(() {
                            _lookupKey = value;
                            _lookupTextFieldController?.text = value!;
                          });
                        },
                        value: _scanItems.isNotEmpty
                            ? _lookupTextFieldController!.text.isEmpty
                                ? _scanItems[0]
                                : _lookupTextFieldController?.text
                            : '',
                      ),
                    ),
                    _isScanLoading
                        ? const Loading()
                        : Container(
                            width: 150,
                            margin: const EdgeInsets.all(15),
                            child: TextButton(
                              child: const Text(
                                'Scan',
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                              ),
                              onPressed: () async {
                                setState(() => _isScanLoading = true);
                                List<AtKey> response =
                                    await _clientSdkService.getAtKeys(
                                  sharedBy: atSign,
                                );
                                if (response.isNotEmpty) {
                                  List<String?> scanList = response
                                      .map((AtKey atKey) => atKey.key)
                                      .toList();
                                  setState(() => _scanItems = scanList);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      response.isEmpty
                                          ? 'Keys list is empty'
                                          : 'Scanning keys and values done.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                );
                                setState(() => _isScanLoading = false);
                              },
                            ),
                          ),
                  ],
                ),
              ),
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              color: Colors.white,
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListTile(
                      title: const Text(
                        'LookUp',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 20.0,
                        ),
                      ),
                      subtitle: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          TextField(
                            decoration:
                                const InputDecoration(hintText: 'Enter Key'),
                            controller: _lookupTextFieldController,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Lookup Result : ',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _lookupValue ?? '',
                            style: const TextStyle(
                              color: Colors.teal,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _isLookupLoading
                        ? const Loading()
                        : Container(
                            margin: const EdgeInsets.all(10),
                            child: TextButton(
                              child: const Text(
                                'Lookup',
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                              ),
                              onPressed: () async {
                                setState(() => _isLookupLoading = true);
                                if (_lookupKey == null) {
                                  setState(
                                      () => _lookupValue = 'The key is empty.');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'The key is empty.',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                } else {
                                  AtKey lookup = AtKey();
                                  lookup.key = _lookupKey;
                                  lookup.sharedWith = atSign;
                                  String? response =
                                      await _clientSdkService.get(lookup);
                                  setState(() => _lookupValue = response);
                                }
                                setState(() => _isLookupLoading = false);
                              },
                            ),
                          ),
                  ],
                ),
              ),
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              color: Colors.white,
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18.0),
                child: Column(
                  children: [
                    ListTile(
                      title: const Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 20.0,
                        ),
                      ),
                      subtitle: TextField(
                        decoration:
                            const InputDecoration(hintText: 'Enter Key'),
                        onChanged: (String key) {
                          setState(() => _deleteKey = key);
                        },
                      ),
                    ),
                    _isDeleteLoading
                        ? const Loading()
                        : Container(
                            width: 150,
                            margin: const EdgeInsets.all(10),
                            child: TextButton(
                              child: const Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                              ),
                              onPressed: () async {
                                setState(() => _isDeleteLoading = true);
                                if (_deleteKey != null) {
                                  AtKey pair = AtKey()
                                    ..key = _deleteKey
                                    ..sharedWith = atSign;
                                  bool _delete =
                                      await _clientSdkService.delete(pair);
                                  if (_delete) {
                                    _lookupTextFieldController?.clear();
                                    _scanItems.remove(pair.key);
                                    _lookupValue = '';
                                    _keyTextFieldController?.clear();
                                    _valueTextFieldController?.clear();
                                    setState(() {});
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _delete
                                            ? '${pair.key} value deleted'
                                            : 'Please make sure key exists.',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                }
                                setState(() => _isDeleteLoading = false);
                              },
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(10.0),
      child: SizedBox(
        height: 35,
        width: 35,
        child: CircularProgressIndicator(),
      ),
    );
  }
}

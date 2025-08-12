<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

# at_chat_flutter example

The at_chat_flutter package is designed to make it easy to add a chat feature between atSigns to any flutter app built on the atPlatform.

### Give it a try
This package includes a working sample application in the [example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_chat_flutter/example) directory that demonstrates the key features of the package. To create a personalized copy, use ```at_app create``` as shown below or check it out on GitHub.

```sh
$ flutter pub global activate at_app 
$ at_app create --sample=<package ID> <app name> 
$ cd <app name>
$ flutter run
```
Notes: 
1. You only need to run ```flutter pub global activate``` once
2. Use ```at_app.bat``` for Windows

For more details head over to [at_app Flags](https://pub.dev/packages/at_app#executable) documentation.

**What will be this doing?**
  - This command will generate a simple skeleton of your at_app.
  - Go to the `.env` file and add your namespace if you haven't passed it as an argument.


## How it works

Like most applications built for the atPlatform, we start with the [at_onboarding_flutter](https://pub.dev/packages/at_onboarding_flutter) widget which handles secure management of secret keys for an atsign as cryptographically secure 
replacement for usernames and passwords.

After onboarding, the second screen will have the app functionality.

The package includes the following UI components:
- The chat screen as a full page
- The chat screen in a bottom sheet

You can customise them as described in the third screen sample usage. The package also manages all the data it needs for you

### Sample Usage

The app needs to initialise the chat service
```
initializeChatService(atClientManager, activeAtSign!,
        rootDomain: AtEnv.rootDomain);
```

As a bottom sheet
```
FlatButton(
    onPressed: () {
        scaffoldKey.currentState
        .showBottomSheet((context) => ChatScreen());
    },
    child: Container(
        height: 40,
        child: Text('Open chat in bottom sheet'),
    ),
),
```

As a screen
```
class ThirdScreen extends StatefulWidget {
  @override
  _ThirdScreenState createState() => _ThirdScreenState();
}

class _ThirdScreenState extends State<ThirdScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat Screen')),
      body: ChatScreen(
        height: MediaQuery.of(context).size.height,
        incomingMessageColor: Colors.blue[100],
        outgoingMessageColor: Colors.green[100],
        isScreen: true,
      ),
    );
  }
}
```

Like everything else we do, this package and even the sample application are open source software which means we love it when you gift us with your feedback, contributions and even any bugs that you help us to discover. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
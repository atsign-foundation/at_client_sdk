<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

## at_contacts_flutter example
The at_contacts_flutter package is designed to make it easy to manage contacts in a flutter app with the following features:
- Create new contact
- Delete a contact
- Block/Unblock a contact

### Give it a try
This package includes a working sample application in the [example](https://github.com/atsign-foundation/at_widgets/tree/trunk/at_contacts_flutter/example) directory that demonstrates the key features of the package. To create a personalized copy, use ```at_app create``` as shown below or check it out on GitHub.

```sh
$ flutter pub global activate at_app 
$ at_app create --sample=<package ID> <app name> 
$ cd <app name>
$ flutter run
```
Notes: 
1. You only need to run ```flutter pub global activate``` once
2. Use ```at_app.bat``` for Windows


## How it works

Like most applications built for the atPlatform, we start with the [at_onboarding_flutter](https://pub.dev/packages/at_onboarding_flutter) widget which handles secure management of secret keys for an atsign as cryptographically secure replacement for usernames and passwords.

After onboarding, this package can fetch a list of already added contacts. This can be either displayed in a custom UI or one can use the UI screens provided in the package.

The package includes the following UI components:
- ContactsScreen - a contacts' list screen for mobile/tablet
- BlockedScreen - a blocked contacts' list screen
- DesktopContactsScreen - a contacts' list screen for desktop apps

The package also manages all the data it needs for you.

## Implementation details

### Initialisation

This package needs to be initialised using:
```
initializeContactsService(rootDomain: AtEnv.rootDomain);
```

If you are using UI widgets from the package then you also have to initialise SizeConfig service.
```
SizeConfig().init(context);
```

### Contacts' list screen

To load the contacts' list screen:
```
ElevatedButton(
	onPressed: () {
		// any logic
		Navigator.of(context).push(MaterialPageRoute(
			builder: (BuildContext context) => const ContactsScreen(),
		));
	},
	child: const Text('Show contacts'),
),
```

### Blocked contacts' list screen

To load the blocked contacts' list screen:
```
ElevatedButton(
	onPressed: () {
		// any logic
		Navigator.of(context).push(MaterialPageRoute(
			builder: (BuildContext context) => const BlockedScreen(),
		));
	},
	child: const Text('Show blocked contacts'),
),
```

### To add a contact
```
ElevatedButton(
	onPressed: () async => showDialog(
		context: context,
		builder: (context) => const AddContactDialog(),
	),
	child: const Text('Add contact'),
),
```

Like everything else we do, this package and even the sample application are open source software which means we love it when you gift us with your feedback, contributions and even any bugs that you help us to discover. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how 
to setup tools, tests and make a pull request.

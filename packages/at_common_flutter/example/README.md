<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

# at_common_flutter example

In this example app we demo at_common_flutter - A Flutter package to provide common widgets used by other atPlatform Flutter packages.

### Give it a try
This package includes a working sample application in the [example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_common_flutter/example) directory that demonstrates the key features of the package. To create a personalized copy, use ```at_app create``` as shown below or check it out on GitHub.

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

The package includes the following UI components:
- CustomAppBar
- CustomInputField
- CustomButton

and a size configuration service:
- SizeConfig

The sample usage of these widgets are as follows:
#### CustomAppBar
```
    return Scaffold(
      appBar: CustomAppBar(
        showBackButton: false,
        showTitle: true,
        titleText: widget.title,
        onTrailingIconPressed: () {
          print('Trailing icon of appbar pressed');
        },
        showTrailingIcon: true,
        trailingIcon: Center(
          child: Icon(
            Icons.add,
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.black
                : Colors.white,
          ),
        ),
      ),
    );
```

#### CustomButton
```
CustomButton(
    height: 50.0,
    width: 200.0,
    buttonText: 'Add',
    onPressed: () {
    print('Custom button pressed');
    },
    buttonColor: Theme.of(context).brightness == Brightness.light
        ? Colors.black
        : Colors.white,
    fontColor: Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : Colors.black,
),
```

#### CustomInputField
```
CustomInputField(
    icon: Icons.emoji_emotions_outlined,
    width: 200.0,
    initialValue: "initial value",
    value: (String val) {
    print('Current value of input field: $val');
    },
),
```

#### SizeConfig service
This service is used to adjust height of widget based upon the screen size.
This service needs to be initialised before usage.
```
import 'package:at_common_flutter/at_common_flutter.dart' as CommonWidgets;

CommonWidgets.SizeConfig().init(context);
```

Like everything else we do, this package and even the sample application are open source software which means we love it when you gift us with your feedback, contributions and even any bugs that you help us to discover. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.

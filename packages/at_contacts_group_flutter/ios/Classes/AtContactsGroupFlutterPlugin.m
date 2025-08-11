#import "AtContactsGroupFlutterPlugin.h"
#if __has_include(<at_contacts_group_flutter/at_contacts_group_flutter-Swift.h>)
#import <at_contacts_group_flutter/at_contacts_group_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "at_contacts_group_flutter-Swift.h"
#endif

@implementation AtContactsGroupFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAtContactsGroupFlutterPlugin registerWithRegistrar:registrar];
}
@end

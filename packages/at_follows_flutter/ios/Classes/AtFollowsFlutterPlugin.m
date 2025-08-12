#import "AtFollowsFlutterPlugin.h"
#if __has_include(<at_follows_flutter/at_follows_flutter-Swift.h>)
#import <at_follows_flutter/at_follows_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "at_follows_flutter-Swift.h"
#endif

@implementation AtFollowsFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAtFollowsFlutterPlugin registerWithRegistrar:registrar];
}
@end

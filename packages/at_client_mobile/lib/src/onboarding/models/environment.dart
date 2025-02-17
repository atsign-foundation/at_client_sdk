/// Secondaries are shared between Dev and Staging. Dev and Staging are unstable environments
enum RootEnvironment {
  dev,
  staging,
  prod,
}

extension Value on RootEnvironment {
  String get domain {
    switch (this) {
      case RootEnvironment.dev:
        return 'my.atsign.wtf ';
      case RootEnvironment.staging:
        return 'my.staging.atsign.wtf';
      case RootEnvironment.prod:
        return 'my.atsign.com';
      default:
        return 'my.atsign.com';
    }
  }

  String get website {
    switch (this) {
      case RootEnvironment.dev:
        return 'https://atsign.wtf';
      case RootEnvironment.prod:
        return 'https://atsign.com';
      case RootEnvironment.staging:
        return 'https://atsign.wtf';
      default:
        return 'https://atsign.wtf';
    }
  }

  String get previewLink {
    switch (this) {
      case RootEnvironment.dev:
        return 'https://directory.atsign.wtf/';
      case RootEnvironment.prod:
        return 'https://wavi.ng/';
      case RootEnvironment.staging:
        return 'https://directory.atsign.wtf/';
      default:
        return 'https://directory.atsign.wtf/';
    }
  }
}

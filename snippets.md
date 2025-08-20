# at_onboarding_cli Shell Testing Snippets

## Testing the --root-server Flag Changes

### 1. Show Help Output

```bash
dart run bin/activate_cli.dart --help
```

Output shows both flags:

```
-r, --rootServer            atDirectory (aka root) server's domain name (deprecated, use --root-server instead)
                            (defaults to "root.atsign.org")
    --root-server           atDirectory (aka root) server domain (e.g., root.atsign.org). Replaces deprecated --rootServer
                            (defaults to "root.atsign.org")
```

### 2. Test Deprecated --rootServer Flag

```bash
$ dart run bin/activate_cli.dart --atsign @test --rootServer test.root.com status -y
Warning: --rootServer is deprecated, please use --root-server instead.
[Information] Onboarding your atSign. This may take up to 2 minutes.
[Information] Requesting my.atsign.com to send a verification code
```

### 3. Test New --root-server Flag

```bash
$ dart run bin/activate_cli.dart --atsign @test --root-server new.root.com status -y
[Information] Onboarding your atSign. This may take up to 2 minutes.
[Information] Requesting my.atsign.com to send a verification code
```

### 4. Test Both Flags Simultaneously

```bash
$ dart run bin/activate_cli.dart --atsign @test --rootServer old.root.com --root-server new.root.com status -y
Warning: Both --rootServer and --root-server provided. Using --root-server value: new.root.com
Note: --rootServer is deprecated, please use --root-server instead.
[Information] Onboarding your atSign. This may take up to 2 minutes.
[Information] Requesting my.atsign.com to send a verification code
```

### 5. Test Default Value (No Flag Provided)

```bash
dart run bin/activate_cli.dart --atsign @test status -y
[Information] Onboarding your atSign. This may take up to 2 minutes.
[Information] Requesting my.atsign.com to send a verification code
```

### 6. Test with Short Flag Alias

```bash
$ dart run bin/activate_cli.dart -a @test -r custom.root.com status -y
Warning: --rootServer is deprecated, please use --root-server instead.
[Information] Onboarding your atSign. This may take up to 2 minutes.
[Information] Requesting my.atsign.com to send a verification code
```

## Quick Test Commands

```bash
# Setup dependencies
dart pub get

# Test help
dart run bin/activate_cli.dart --help

# Test deprecated flag warning
dart run bin/activate_cli.dart -a @test -r old.root.com status -y 2>&1 | head -5

# Test new flag (no warning)
dart run bin/activate_cli.dart -a @test --root-server new.root.com status -y 2>&1 | head -5

# Test both flags (new one wins)
dart run bin/activate_cli.dart -a @test -r old.root.com --root-server new.root.com status -y 2>&1 | head -5
```

## Key Observations

1. **Deprecation Warning**: The old `--rootServer` (or `-r`) flag shows a clear deprecation warning
2. **Backward Compatibility**: Old flag still works, ensuring existing scripts don't break
3. **Priority**: When both flags are provided, `--root-server` takes precedence
4. **Default Behavior**: When neither flag is provided, defaults to `root.atsign.org`
5. **Help Text**: Both flags are documented in help, with deprecation notice for old flag

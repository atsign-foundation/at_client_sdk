import 'package:flutter/material.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:example/walkthrough.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,

        // Scaffold theme
        scaffoldBackgroundColor: Colors.white,

        // AppBar theme
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),

        // Text theme
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          bodyMedium: TextStyle(fontSize: 14),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          bodySmall: TextStyle(fontSize: 13),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),

        // Elevated button theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // Outlined button theme
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            elevation: 0,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // Text button theme
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),

        // Divider theme
        dividerTheme: const DividerThemeData(thickness: 1),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      // Uses theme.scaffoldBackgroundColor automatically
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Title - using theme text style
                Text('My App', style: textTheme.headlineMedium),

                const SizedBox(height: 8),

                // Subtitle - using theme text style with color modification
                Text(
                  'Secure authentication with atSign',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),

                const SizedBox(height: 48),

                // Login Button - now calls loginWithKeychain
                ElevatedButton(
                  onPressed: () async {
                    await loginWithKeychain(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: const Text('Login with Existing atSign'),
                ),

                const SizedBox(height: 16),

                // Divider with "OR" - using theme divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 16),

                // Register Button - now says "Onboard a New atSign"
                OutlinedButton(
                  onPressed: () async {
                    await onboard(context);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    side: BorderSide(
                      color: colorScheme.primary.withOpacity(0.5),
                    ),
                  ),
                  child: const Text('Onboard a New atSign'),
                ),

                const SizedBox(height: 16),

                // NEW: Add atSign by File Button
                OutlinedButton(
                  onPressed: () async {
                    await loginWithFile(context);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.secondary,
                    side: BorderSide(
                      color: colorScheme.secondary.withOpacity(0.5),
                    ),
                  ),
                  child: const Text('Add an atSign by File'),
                ),

                const SizedBox(height: 16),

                // Manage Paired atSigns text button - using theme
                TextButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      builder: (BuildContext context) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header - using theme text style
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Text(
                                  'Manage Paired atSigns',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(
                                      0.8,
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(),

                              // Clear atSign option - using theme colors
                              ListTile(
                                leading: Icon(
                                  Icons.clear,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('Clear atSign'),
                                onTap: () async {
                                  await removeAtsign(context);
                                  Navigator.pop(context);
                                },
                              ),

                              // Reset all atSigns option - using theme colors
                              ListTile(
                                leading: Icon(
                                  Icons.restore,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('Reset All atSigns'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await clearAllAtsigns();
                                },
                              ),

                              const SizedBox(height: 10),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  child: Text(
                    'Manage Paired atSigns',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Footer text - using theme text style
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      Text(
                        "Don't have an atSign yet?",
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Get a free atSign at atsign.com',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    bool _isExporting = false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        automaticallyImplyLeading: false, // Removes back button
      ),
      body: Center(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () {
                AtClientManager.getInstance().reset();
                // Navigate back to login page
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const MyHomePage()),
                );
              },
              child: const Text('Logout'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await exportKeys(context);
              },
              icon: const Icon(Icons.download),
              label: Text('Export AtSign Keys'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

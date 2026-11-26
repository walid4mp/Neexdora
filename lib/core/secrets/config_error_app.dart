import 'package:flutter/material.dart';

/// Shown instead of the app when Supabase settings were not compiled in.
/// Prints only the NAMES of the missing settings — never any value.
class ConfigErrorApp extends StatelessWidget {
  final List<String> missing;
  const ConfigErrorApp({super.key, required this.missing});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_suggest_rounded, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'App configuration is incomplete',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This build was created without: ${missing.isEmpty ? 'a valid SUPABASE_URL' : missing.join(', ')}.\n'
                    'Rebuild with --dart-define-from-file=ci.env.json '
                    '(GitHub Actions: workflow "Web build").',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

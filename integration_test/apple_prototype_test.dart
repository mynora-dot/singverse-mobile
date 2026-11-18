import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'library_glass_test.dart' as catalog;
import 'nas_glass_test.dart' as nas;
import 'phone_failure_reporter.dart';
import 'player_console_test.dart' as player;

/// Registers the existing suites in one .e2e APK for one USB installation.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installPhoneFailureReporter(binding);
  final reports = <String, Map<String, dynamic>>{};

  void registerSuite(String name, void Function() register) {
    group(name, () {
      setUp(() => binding.reportData = null);
      tearDownAll(() {
        final report = binding.reportData;
        if (report != null) {
          reports[name] = Map<String, dynamic>.from(report);
        }
        // Preserve native checks/scenarios at the driver's existing top level.
        // Missing reports do not hide test failures or pass report validation.
        binding.reportData = {
          ...?reports['player_console'],
          'uiSuites': {
            for (final ui in ['library_glass', 'nas_glass'])
              if (reports.containsKey(ui)) ui: reports[ui],
          },
          'bundle': {
            'suites': reports.keys.toList(),
            'preferences':
                'UI SharedPreferences fixtures remain in memory; '
                'the player still uses real NAS, Media3 and AudioRecord.',
          },
        };
      });
      register();
    });
  }

  // Library's existing teardown removes both native method-channel mocks
  // before the next suite; NAS also disposes its own in-memory state/store.
  registerSuite('library_glass', catalog.main);
  registerSuite('nas_glass', nas.main);
  registerSuite('player_console', player.main);
}

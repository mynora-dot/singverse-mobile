import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';

IntegrationTestWidgetsFlutterBinding? _installedBinding;

/// Retains framework failure reporting and serializes useful profile details.
void installPhoneFailureReporter(IntegrationTestWidgetsFlutterBinding binding) {
  if (identical(_installedBinding, binding)) return;
  _installedBinding = binding;
  final previousReporter = reportTestException;
  reportTestException = (details, description) {
    try {
      previousReporter(details, description);
    } finally {
      final stack = details.stack?.toString();
      binding.results[description] = Failure(
        description,
        '${details.exceptionAsString()}${stack == null ? '' : '\n$stack'}',
      );
    }
  };
}

import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['SINGVERSE_LIBRARY_GLASS_OUTPUT'] ??
        'build/reports/singverse-design-system-v3/android',
  );
  await output.create(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File('${output.path}/report.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['SINGVERSE_NAS_GLASS_OUTPUT'] ??
        'build/reports/nas-liquid-optics-v2/android',
  );
  await output.create(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {});
      report.remove('screenshots');
      await File('${output.path}/report.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}

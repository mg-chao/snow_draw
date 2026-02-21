import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('melos architecture script includes required guard steps', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('check:architecture:'));
    expect(pubspec, contains('check:core-purity'));
    expect(pubspec, contains('check:backend-legacy'));
    expect(pubspec, contains('check:backend-entrypoint'));
    expect(pubspec, contains('check:ci-workflow'));
    expect(pubspec, contains('check:app-backend-import-boundary'));
  });
}

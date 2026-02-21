import 'dart:convert';
import 'dart:io';

const _appPackageName = 'snow_draw';
const _appPackagePath = 'apps/snow_draw';
const _requiredBackendPackageName = 'snow_draw_flutter_backend';
const _requiredCorePackageName = 'snow_draw_core';
const _requiredFlutterSdkPackage = 'flutter';

void main() {
  final result = Process.runSync('dart', const [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: _appPackagePath);

  if (result.exitCode != 0) {
    stderr.writeln('Failed to resolve dependency graph for $_appPackageName.');
    if (result.stderr.toString().trim().isNotEmpty) {
      stderr.writeln(result.stderr);
    }
    exitCode = 1;
    return;
  }

  final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final rawPackages = decoded['packages'];
  if (rawPackages is! List<Object?>) {
    stderr.writeln('Unexpected dependency graph format: missing "packages".');
    exitCode = 1;
    return;
  }

  final packages = <String, _PackageInfo>{};
  for (final raw in rawPackages) {
    if (raw is! Map<String, Object?>) {
      continue;
    }
    final name = raw['name'];
    final source = raw['source'];
    final dependencies = raw['dependencies'];
    if (name is! String ||
        source is! String ||
        dependencies is! List<Object?>) {
      continue;
    }
    packages[name] = _PackageInfo(
      name: name,
      source: source,
      dependencies: dependencies.whereType<String>().toList(growable: false),
    );
  }

  if (!packages.containsKey(_appPackageName)) {
    stderr.writeln(
      'Dependency graph does not contain app package "$_appPackageName".',
    );
    exitCode = 1;
    return;
  }

  final reachable = <String>{};
  final queue = <String>[_appPackageName];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (!reachable.add(current)) {
      continue;
    }
    final package = packages[current];
    if (package == null) {
      continue;
    }
    queue.addAll(package.dependencies);
  }

  final violations = <String>[];
  if (!reachable.contains(_requiredCorePackageName)) {
    violations.add(
      'Missing required reachable package "$_requiredCorePackageName" from '
      '$_appPackageName.',
    );
  }
  if (!reachable.contains(_requiredBackendPackageName)) {
    violations.add(
      'Missing required reachable package "$_requiredBackendPackageName" from '
      '$_appPackageName.',
    );
  }

  final flutterPackage = packages[_requiredFlutterSdkPackage];
  if (!reachable.contains(_requiredFlutterSdkPackage) ||
      flutterPackage == null ||
      flutterPackage.source != 'sdk') {
    violations.add(
      'App package must resolve Flutter SDK package '
      '"$_requiredFlutterSdkPackage" as an SDK dependency.',
    );
  }

  if (violations.isNotEmpty) {
    stderr.writeln('App dependency graph boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'App dependency graph boundary check passed. '
    'App reaches core/backend/flutter dependencies.',
  );
}

class _PackageInfo {
  const _PackageInfo({
    required this.name,
    required this.source,
    required this.dependencies,
  });

  final String name;
  final String source;
  final List<String> dependencies;
}

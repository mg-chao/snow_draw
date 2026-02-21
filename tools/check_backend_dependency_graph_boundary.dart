import 'dart:convert';
import 'dart:io';

const _backendPackageName = 'snow_draw_flutter_backend';
const _backendPackagePath = 'packages/snow_draw_flutter_backend';
const _requiredCorePackageName = 'snow_draw_core';
const _forbiddenAppPackageName = 'snow_draw';
const _requiredFlutterSdkPackage = 'flutter';

void main() {
  final result = Process.runSync('dart', const [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: _backendPackagePath);

  if (result.exitCode != 0) {
    stderr.writeln(
      'Failed to resolve dependency graph for $_backendPackageName.',
    );
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

  if (!packages.containsKey(_backendPackageName)) {
    stderr.writeln(
      'Dependency graph does not contain backend package "$_backendPackageName".',
    );
    exitCode = 1;
    return;
  }

  final parents = <String, String?>{};
  final reachable = <String>{};
  final queue = <String>[_backendPackageName];
  parents[_backendPackageName] = null;

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (!reachable.add(current)) {
      continue;
    }
    final package = packages[current];
    if (package == null) {
      continue;
    }
    for (final dependency in package.dependencies) {
      if (!parents.containsKey(dependency)) {
        parents[dependency] = current;
      }
      queue.add(dependency);
    }
  }

  final violations = <String>[];
  if (!reachable.contains(_requiredCorePackageName)) {
    violations.add(
      'Missing required reachable package "$_requiredCorePackageName" from '
      '$_backendPackageName.',
    );
  }
  if (reachable.contains(_forbiddenAppPackageName)) {
    final chain = _buildChain(
      target: _forbiddenAppPackageName,
      parents: parents,
    );
    violations.add(
      'Forbidden app package "$_forbiddenAppPackageName" is reachable from '
      '$_backendPackageName'
      '${chain.length > 1 ? ' via ${chain.join(' -> ')}' : ''}.',
    );
  }

  final flutterPackage = packages[_requiredFlutterSdkPackage];
  if (!reachable.contains(_requiredFlutterSdkPackage) ||
      flutterPackage == null ||
      flutterPackage.source != 'sdk') {
    violations.add(
      'Backend package must resolve Flutter SDK package '
      '"$_requiredFlutterSdkPackage" as an SDK dependency.',
    );
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend dependency graph boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend dependency graph boundary check passed. '
    'Backend reaches core/flutter and does not reach app package.',
  );
}

List<String> _buildChain({
  required String target,
  required Map<String, String?> parents,
}) {
  final chain = <String>[];
  String? cursor = target;
  while (cursor != null) {
    chain.add(cursor);
    cursor = parents[cursor];
  }
  return chain.reversed.toList(growable: false);
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

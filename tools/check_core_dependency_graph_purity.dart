import 'dart:convert';
import 'dart:io';

const _corePackageName = 'snow_draw_core';
const _corePackagePath = 'packages/snow_draw_core';
const _forbiddenWorkspacePackages = <String>{
  'snow_draw_flutter_backend',
  'snow_draw',
};

void main() {
  final result = Process.runSync('dart', const [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: _corePackagePath);

  if (result.exitCode != 0) {
    stderr.writeln('Failed to resolve dependency graph for $_corePackageName.');
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

  if (!packages.containsKey(_corePackageName)) {
    stderr.writeln(
      'Dependency graph does not contain core package "$_corePackageName".',
    );
    exitCode = 1;
    return;
  }

  final parents = <String, String?>{};
  final reachable = <String>{};
  final queue = <String>[_corePackageName];
  parents[_corePackageName] = null;

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
  final sdkViolations = <_PackageInfo>[];
  for (final packageName in reachable) {
    final package = packages[packageName];
    if (package == null) {
      continue;
    }
    if (package.source == 'sdk' && !_isAllowedSdkPackage(package.name)) {
      sdkViolations.add(package);
    }
  }

  if (sdkViolations.isNotEmpty) {
    sdkViolations.sort((a, b) => a.name.compareTo(b.name));
    violations.add(
      'Reachable SDK packages from $_corePackageName must be Dart-only; '
      'found disallowed SDK package(s):',
    );
    for (final sdkViolation in sdkViolations) {
      final chain = _buildChain(target: sdkViolation.name, parents: parents);
      violations.add(
        '- ${sdkViolation.name} (source: ${sdkViolation.source})'
        '${chain.length > 1 ? ' via ${chain.join(' -> ')}' : ''}',
      );
    }
  }

  for (final forbiddenPackage in _forbiddenWorkspacePackages) {
    if (!reachable.contains(forbiddenPackage)) {
      continue;
    }
    final chain = _buildChain(target: forbiddenPackage, parents: parents);
    violations.add(
      'Forbidden workspace package "$forbiddenPackage" is reachable from '
      '$_corePackageName'
      '${chain.length > 1 ? ' via ${chain.join(' -> ')}' : ''}.',
    );
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Core dependency graph purity check failed.');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Core dependency graph purity check passed. '
    'No disallowed SDK packages or forbidden workspace packages are reachable '
    'from $_corePackageName.',
  );
}

bool _isAllowedSdkPackage(String packageName) {
  // pub deps may include SDK packages for Flutter graphs. Core must never
  // reach them.
  return packageName == 'dart';
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

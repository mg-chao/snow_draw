import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String releaseWorkflow;
  late String deployPagesWorkflow;

  setUpAll(() {
    releaseWorkflow = _readWorkflow('release.yml');
    deployPagesWorkflow = _readWorkflow('deploy-pages.yml');
  });

  group('release workflow baseline behavior', () {
    test('still builds windows and web artifacts from semantic tags', () {
      expect(releaseWorkflow, contains('tags:'));
      expect(releaseWorkflow, contains("- 'v*.*.*'"));
      expect(releaseWorkflow, contains('workflow_dispatch:'));
      expect(releaseWorkflow, contains('flutter build windows --release'));
      expect(releaseWorkflow, contains('flutter build web --release'));
      expect(releaseWorkflow, contains('snow_draw-windows-x64.zip'));
      expect(releaseWorkflow, contains('snow_draw-web.tar.gz'));
    });

    test('still creates a draft GitHub release with both assets', () {
      expect(releaseWorkflow, contains('softprops/action-gh-release@v1'));
      expect(releaseWorkflow, contains('draft: true'));
      expect(releaseWorkflow, contains('name: Download Windows artifact'));
      expect(releaseWorkflow, contains('name: Download Web artifact'));
    });
  });

  group('release workflow hardening', () {
    test('validates manual version input before creating release', () {
      expect(releaseWorkflow, contains('name: Validate version format'));
      expect(releaseWorkflow, contains('Invalid version'));
      expect(releaseWorkflow, contains(r'^v[0-9]+\.[0-9]+\.[0-9]+'));
      expect(releaseWorkflow, contains(r'(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?'));
      expect(
        releaseWorkflow,
        contains(r'(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?'),
      );
    });

    test('uses repository-derived GitHub Pages URL in release notes', () {
      expect(releaseWorkflow, contains('const pagesUrl ='));
      expect(releaseWorkflow, contains('context.repo.owner'));
      expect(releaseWorkflow, contains('context.repo.repo'));
      expect(
        releaseWorkflow,
        isNot(contains('https://mg-chao.github.io/snow_draw/')),
      );
    });

    test('fails fast when expected build artifacts are missing', () {
      final strictUploadCount = _countMatches(
        releaseWorkflow,
        'if-no-files-found: error',
      );
      expect(strictUploadCount, greaterThanOrEqualTo(2));
    });

    test('uses workspace-local melos commands', () {
      final bootstrapCount = _countMatches(
        releaseWorkflow,
        'dart run melos bootstrap',
      );
      expect(bootstrapCount, greaterThanOrEqualTo(2));
      expect(
        releaseWorkflow,
        isNot(contains('dart pub global activate melos')),
      );
    });

    test('uses stable Flutter channel for deterministic CI builds', () {
      final stableChannelCount = _countMatches(
        releaseWorkflow,
        'channel: stable',
      );
      expect(stableChannelCount, greaterThanOrEqualTo(3));
      expect(releaseWorkflow, isNot(contains('channel: beta')));
    });

    test('runs quality gates before platform-specific build jobs', () {
      expect(releaseWorkflow, contains('quality-gate:'));
      expect(
        releaseWorkflow,
        contains('needs: [quality-gate, build-windows, build-web]'),
      );
      final qualityGateDependencyCount = _countMatches(
        releaseWorkflow,
        'needs: quality-gate',
      );
      expect(qualityGateDependencyCount, greaterThanOrEqualTo(2));
      expect(releaseWorkflow, contains('dart run melos run analyze'));
      expect(releaseWorkflow, contains('dart run melos run format:check'));
      expect(releaseWorkflow, contains('dart run melos run test'));
    });

    test('derives prerelease flag from version string', () {
      expect(releaseWorkflow, contains('name: Derive release channel'));
      expect(releaseWorkflow, contains('prerelease=true'));
      expect(releaseWorkflow, contains('prerelease=false'));
      expect(
        releaseWorkflow,
        contains(
          r'prerelease: ${{ steps.release_channel.outputs.prerelease }}',
        ),
      );
    });

    test('prevents manual releases from overwriting existing tags', () {
      expect(releaseWorkflow, contains('name: Validate tag availability'));
      expect(
        releaseWorkflow,
        contains("if: github.event_name == 'workflow_dispatch'"),
      );
      expect(releaseWorkflow, contains('git fetch --tags --force'));
      expect(
        releaseWorkflow,
        contains(r'git show-ref --verify --quiet "refs/tags/$version"'),
      );
      expect(releaseWorkflow, contains('already exists'));
      expect(releaseWorkflow, contains('fetch-depth: 0'));
    });
  });

  group('deploy pages workflow optimization', () {
    test('uses current pages artifact action version', () {
      expect(deployPagesWorkflow, contains('actions/upload-pages-artifact@v4'));
    });

    test('uses workspace-local melos commands', () {
      expect(deployPagesWorkflow, contains('dart run melos bootstrap'));
      expect(
        deployPagesWorkflow,
        isNot(contains('dart pub global activate melos')),
      );
    });

    test('uses stable Flutter channel for deterministic deployments', () {
      expect(deployPagesWorkflow, contains('channel: stable'));
      expect(deployPagesWorkflow, isNot(contains('channel: beta')));
    });
  });

  group('workflow execution optimization', () {
    test('avoids redundant dart pub get calls when melos bootstrap runs', () {
      expect(releaseWorkflow, isNot(contains('dart pub get')));
      expect(deployPagesWorkflow, isNot(contains('dart pub get')));
    });

    test('applies timeout limits to all release workflow jobs', () {
      expect(
        _extractJobBlock(releaseWorkflow, 'quality-gate'),
        contains('timeout-minutes:'),
      );
      expect(
        _extractJobBlock(releaseWorkflow, 'build-windows'),
        contains('timeout-minutes:'),
      );
      expect(
        _extractJobBlock(releaseWorkflow, 'build-web'),
        contains('timeout-minutes:'),
      );
      expect(
        _extractJobBlock(releaseWorkflow, 'create-release'),
        contains('timeout-minutes:'),
      );
    });

    test('applies timeout limits to deploy pages workflow jobs', () {
      expect(
        _extractJobBlock(deployPagesWorkflow, 'build'),
        contains('timeout-minutes:'),
      );
      expect(
        _extractJobBlock(deployPagesWorkflow, 'deploy'),
        contains('timeout-minutes:'),
      );
    });
  });
}

String _readWorkflow(String workflowFileName) {
  final repoRoot = _findRepoRoot();
  final workflowFile = File(
    _joinPath([repoRoot.path, '.github', 'workflows', workflowFileName]),
  );

  if (!workflowFile.existsSync()) {
    throw StateError('Workflow file not found: ${workflowFile.path}');
  }

  return workflowFile.readAsStringSync();
}

Directory _findRepoRoot() {
  var directory = Directory.current;

  while (true) {
    final releaseWorkflow = File(
      _joinPath([directory.path, '.github', 'workflows', 'release.yml']),
    );

    if (releaseWorkflow.existsSync()) {
      return directory;
    }

    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Unable to locate repository root from ${Directory.current.path}.',
      );
    }

    directory = parent;
  }
}

String _joinPath(List<String> segments) =>
    segments.join(Platform.pathSeparator);

String _extractJobBlock(String workflow, String jobName) {
  final jobHeader = RegExp(
    '^  ${RegExp.escape(jobName)}:\\s*\$',
    multiLine: true,
  );
  final jobHeaderMatch = jobHeader.firstMatch(workflow);
  if (jobHeaderMatch == null) {
    throw StateError('Job not found: $jobName');
  }

  final blockStart = jobHeaderMatch.end;
  final nextJobHeader = RegExp(r'^  [A-Za-z0-9_-]+:\s*$', multiLine: true);
  var blockEnd = workflow.length;

  for (final match in nextJobHeader.allMatches(workflow, blockStart)) {
    if (match.start > blockStart) {
      blockEnd = match.start;
      break;
    }
  }

  return workflow.substring(blockStart, blockEnd);
}

int _countMatches(String text, String needle) {
  var count = 0;
  var start = 0;

  while (true) {
    final matchIndex = text.indexOf(needle, start);
    if (matchIndex == -1) {
      return count;
    }

    count += 1;
    start = matchIndex + needle.length;
  }
}

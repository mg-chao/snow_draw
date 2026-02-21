import 'dart:io';

const _ciWorkflowPath = '.github/workflows/ci.yml';

const _requiredCommandsInOrder = <String>[
  'dart run melos run analyze',
  'dart run melos run format:check',
  'dart run melos run check:architecture',
  'dart run melos run check:compatibility-contracts',
  'dart run melos run test',
];

void main() {
  final workflowFile = File(_ciWorkflowPath);
  if (!workflowFile.existsSync()) {
    stderr.writeln('Missing CI workflow file: $_ciWorkflowPath');
    exitCode = 1;
    return;
  }

  final workflow = workflowFile.readAsStringSync();
  final violations = <String>[];
  var lastIndex = -1;
  for (final command in _requiredCommandsInOrder) {
    final index = workflow.indexOf(command);
    if (index < 0) {
      violations.add(
        'Missing required CI command "$command" in $_ciWorkflowPath',
      );
      continue;
    }
    if (index < lastIndex) {
      violations.add(
        'CI command "$command" appears out of order in $_ciWorkflowPath',
      );
      continue;
    }
    lastIndex = index;
  }

  if (violations.isNotEmpty) {
    stderr.writeln('CI workflow guard check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'CI workflow guard check passed. Required architecture and '
    'compatibility gates are present and ordered before tests.',
  );
}

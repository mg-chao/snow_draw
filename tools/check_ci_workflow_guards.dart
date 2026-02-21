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

  final runCommands = _extractRunCommands(workflowFile.readAsLinesSync());
  final violations = <String>[];
  var lastIndex = -1;
  for (final command in _requiredCommandsInOrder) {
    final commandIndexes = <int>[];
    for (var index = 0; index < runCommands.length; index++) {
      if (runCommands[index] == command) {
        commandIndexes.add(index);
      }
    }

    if (commandIndexes.isEmpty) {
      violations.add(
        'Missing required CI command "$command" in $_ciWorkflowPath',
      );
      continue;
    }
    if (commandIndexes.length > 1) {
      violations.add(
        'CI command "$command" must appear exactly once in $_ciWorkflowPath',
      );
      continue;
    }

    final index = commandIndexes.single;
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

List<String> _extractRunCommands(List<String> lines) {
  final commands = <String>[];
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith('run: ')) {
      continue;
    }
    final command = trimmed.substring('run: '.length).trim();
    if (command.isEmpty) {
      continue;
    }
    commands.add(command);
  }
  return commands;
}

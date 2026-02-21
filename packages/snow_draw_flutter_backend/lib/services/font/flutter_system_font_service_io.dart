import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:snow_draw_core/draw/elements/text_rendering_cache_invalidation.dart';

import '../text/flutter_text_rendering_cache_invalidation.dart';

final revisionNotifier = ValueNotifier<int>(0);

final Map<String, _FontFamilyEntry> _fontIndex = {};
final Set<String> _loadedFamilies = {};
final Map<String, Future<void>> _fontLoadTasks = {};
final Map<String, bool> _fileExistsCache = {};

List<String>? _sortedFamilyCache;
Future<void>? _fontIndexTask;

const _windowsFontRegistryPaths = [
  r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
  r'HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
];

final _windowsFontSuffixPattern = RegExp(
  r'\s*\((TrueType|OpenType|Type 1|PostScript|Bitmap|All res)\)',
  caseSensitive: false,
);

final String _windowsFontsDir = _resolveWindowsFontsDir();
final String _windowsUserFontsDir = _resolveWindowsUserFontsDir();

const _macFamilyKeys = ['family', 'name', '_name', 'full_name'];
const _macPathKeys = ['path', 'location', 'file', 'font_path'];

Future<List<String>> listFamiliesImpl() async {
  final cached = _sortedFamilyCache;
  if (cached != null) {
    return cached;
  }

  await _ensureFontIndex();
  final sorted = _sortedFamilyNames();
  _sortedFamilyCache = sorted;
  return sorted;
}

Future<void> ensureLoadedImpl(String family) async {
  final trimmedFamily = family.trim();
  if (trimmedFamily.isEmpty) {
    return;
  }

  await _ensureFontIndex();

  final key = _normalizeFamilyKey(trimmedFamily);
  if (_loadedFamilies.contains(key)) {
    return;
  }

  final inFlightTask = _fontLoadTasks[key];
  if (inFlightTask != null) {
    await inFlightTask;
    return;
  }

  final entry = _fontIndex[key];
  if (entry == null || entry.files.isEmpty) {
    return;
  }

  final task = _loadFontFamily(trimmedFamily, key, entry);
  _fontLoadTasks[key] = task;
  try {
    await task;
  } finally {
    await _fontLoadTasks.remove(key);
  }
}

Future<void> _ensureFontIndex() async {
  final task = _fontIndexTask ??= _buildFontIndex();
  await task;
}

Future<void> _buildFontIndex() async {
  _fontIndex.clear();
  _sortedFamilyCache = null;
  _fileExistsCache.clear();

  try {
    if (Platform.isWindows) {
      await _indexWindowsFonts();
      return;
    }
    if (Platform.isMacOS) {
      await _indexMacFonts();
      return;
    }
    if (Platform.isLinux) {
      await _indexLinuxFonts();
    }
  } on Exception {
    // Ignore discovery failures; callers can fall back to built-in fonts.
  }
}

Future<void> _loadFontFamily(
  String family,
  String key,
  _FontFamilyEntry entry,
) async {
  ensureFlutterTextRenderingCacheInvalidatorInstalled();
  final loader = FontLoader(family);
  var addedFonts = 0;
  for (final path in entry.files) {
    final bytes = await _readFontBytes(path);
    if (bytes == null) {
      continue;
    }
    loader.addFont(Future.value(bytes));
    addedFonts += 1;
  }
  if (addedFonts == 0) {
    return;
  }

  try {
    await loader.load();
    _loadedFamilies.add(key);
    invalidateTextRenderingCaches();
    revisionNotifier.value += 1;
  } on Exception {
    // Ignore load failures; unavailable fonts should not crash drawing.
  }
}

Future<ByteData?> _readFontBytes(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }
    return bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
  } on Exception {
    return null;
  }
}

List<String> _sortedFamilyNames() {
  final names = [for (final entry in _fontIndex.values) entry.displayName];
  return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

Future<void> _indexWindowsFonts() async {
  for (final registryPath in _windowsFontRegistryPaths) {
    final output = await _runCommand('reg', ['query', registryPath]);
    if (output == null) {
      continue;
    }

    for (final record in _parseWindowsRegistryFonts(output)) {
      _addFontEntry(record.name, record.files);
    }
  }
}

Iterable<_FontRecord> _parseWindowsRegistryFonts(String output) sync* {
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('HKEY')) {
      continue;
    }

    final parts = line.split(RegExp(r'\s{2,}'));
    if (parts.length < 3) {
      continue;
    }

    final name = parts[0].replaceAll(_windowsFontSuffixPattern, '').trim();
    if (name.isEmpty) {
      continue;
    }

    final value = parts.sublist(2).join(' ').trim();
    if (value.isEmpty) {
      continue;
    }
    final files = _resolveWindowsFontFiles(value);
    if (files.isEmpty) {
      continue;
    }
    yield _FontRecord(name, files);
  }
}

List<String> _resolveWindowsFontFiles(String value) {
  final cleaned = value.replaceAll('"', '').trim();
  if (cleaned.isEmpty) {
    return const [];
  }

  final files = <String>[];
  for (final rawPart in cleaned.split(RegExp(r'\s*&\s*'))) {
    for (final segment in rawPart.split(RegExp(r'\s*,\s*'))) {
      final part = segment.trim();
      if (part.isEmpty) {
        continue;
      }
      if (_isWindowsAbsolutePath(part)) {
        files.add(part);
        continue;
      }

      files.add('$_windowsFontsDir\\$part');
      if (_windowsUserFontsDir != _windowsFontsDir) {
        files.add('$_windowsUserFontsDir\\$part');
      }
    }
  }
  return files;
}

bool _isWindowsAbsolutePath(String path) =>
    RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');

String _resolveWindowsFontsDir() {
  final root =
      Platform.environment['WINDIR'] ??
      Platform.environment['SystemRoot'] ??
      r'C:\Windows';
  return '$root\\Fonts';
}

String _resolveWindowsUserFontsDir() {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData == null || localAppData.isEmpty) {
    return _windowsFontsDir;
  }
  return '$localAppData\\Microsoft\\Windows\\Fonts';
}

Future<void> _indexLinuxFonts() async {
  final output = await _runCommand('fc-list', ['-f', '%{family}::%{file}\n']);
  if (output == null) {
    return;
  }
  for (final record in _parseFontConfigEntries(output)) {
    _addFontEntry(record.name, record.files);
  }
}

Future<void> _indexMacFonts() async {
  final fcListOutput = await _runCommand('fc-list', [
    '-f',
    '%{family}::%{file}\n',
  ]);
  if (fcListOutput != null) {
    for (final record in _parseFontConfigEntries(fcListOutput)) {
      _addFontEntry(record.name, record.files);
    }
    return;
  }
  final profilerOutput = await _runCommand('system_profiler', [
    'SPFontsDataType',
    '-json',
  ]);
  if (profilerOutput == null) {
    return;
  }
  for (final record in _parseSystemProfilerEntries(profilerOutput)) {
    _addFontEntry(record.name, record.files);
  }
}

Iterable<_FontRecord> _parseFontConfigEntries(String output) sync* {
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final separatorIndex = line.indexOf('::');
    if (separatorIndex <= 0 || separatorIndex + 2 >= line.length) {
      continue;
    }

    final familyPart = line.substring(0, separatorIndex).trim();
    final filePart = line.substring(separatorIndex + 2).trim();
    if (familyPart.isEmpty || filePart.isEmpty) {
      continue;
    }

    for (final family in familyPart.split(',')) {
      final name = family.trim();
      if (name.isEmpty) {
        continue;
      }
      yield _FontRecord(name, [filePart]);
    }
  }
}

Iterable<_FontRecord> _parseSystemProfilerEntries(String output) sync* {
  try {
    final data = jsonDecode(output);
    if (data is! Map<String, Object?>) {
      return;
    }
    final entries = data['SPFontsDataType'];
    if (entries is! List) {
      return;
    }

    for (final rawEntry in entries) {
      if (rawEntry is! Map<String, Object?>) {
        continue;
      }

      final family = _firstString(rawEntry, _macFamilyKeys);
      final path = _firstString(rawEntry, _macPathKeys);
      if (family == null || path == null) {
        continue;
      }
      final trimmedFamily = family.trim();
      final trimmedPath = path.trim();
      if (trimmedFamily.isEmpty || trimmedPath.isEmpty) {
        continue;
      }
      yield _FontRecord(trimmedFamily, [trimmedPath]);
    }
  } on Exception {
    // Ignore malformed system_profiler payloads.
  }
}

String? _firstString(Map<String, Object?> entry, List<String> keys) {
  for (final key in keys) {
    final value = entry[key];
    if (value is String) {
      return value;
    }
  }
  return null;
}

void _addFontEntry(String family, Iterable<String> files) {
  final trimmedFamily = family.trim();
  if (trimmedFamily.isEmpty) {
    return;
  }

  final key = _normalizeFamilyKey(trimmedFamily);
  final entry = _fontIndex.putIfAbsent(
    key,
    () => _FontFamilyEntry(displayName: trimmedFamily),
  );

  for (final file in files) {
    final path = file.trim();
    if (path.isEmpty) {
      continue;
    }

    final exists = _fileExistsCache[path] ??= File(path).existsSync();
    if (exists) {
      entry.files.add(path);
    }
  }
}

String _normalizeFamilyKey(String family) => family.trim().toLowerCase();

Future<String?> _runCommand(String command, List<String> args) async {
  try {
    final result = await Process.run(command, args);
    if (result.exitCode != 0) {
      return null;
    }
    final stdoutText = result.stdout?.toString();
    if (stdoutText == null || stdoutText.trim().isEmpty) {
      return null;
    }
    return stdoutText;
  } on Exception {
    return null;
  }
}

class _FontFamilyEntry {
  _FontFamilyEntry({required this.displayName});

  final String displayName;
  final Set<String> files = {};
}

class _FontRecord {
  const _FontRecord(this.name, this.files);

  final String name;
  final List<String> files;
}

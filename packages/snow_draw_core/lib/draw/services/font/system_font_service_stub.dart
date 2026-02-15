import 'package:flutter/foundation.dart';

/// Web / unsupported-platform stub.
///
/// Returns empty results and never loads anything.

final revisionNotifier = ValueNotifier<int>(0);

Future<List<String>> listFamiliesImpl() async => const [];

Future<void> ensureLoadedImpl(String family) async {}

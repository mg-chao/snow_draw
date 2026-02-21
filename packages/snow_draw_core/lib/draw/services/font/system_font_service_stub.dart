import '../../core/value_listenable.dart';

final revisionNotifier = ValueNotifier<int>(0);

Future<List<String>> listFamiliesImpl() => Future.value(const <String>[]);

Future<void> ensureLoadedImpl(String _) => Future<void>.value();

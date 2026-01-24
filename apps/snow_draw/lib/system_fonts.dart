import 'system_fonts_stub.dart' if (dart.library.io) 'system_fonts_io.dart';

Future<List<String>> loadSystemFontFamilies() => loadSystemFontFamiliesImpl();

Future<void> ensureSystemFontLoaded(String family) =>
    ensureSystemFontLoadedImpl(family);

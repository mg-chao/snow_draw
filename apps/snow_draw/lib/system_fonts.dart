import 'render_backend.dart';

const FlutterSystemFontService _service = FlutterSystemFontService.instance;

Future<List<String>> loadSystemFontFamilies() => _service.listFamilies();

Future<void> ensureSystemFontLoaded(String family) =>
    _service.ensureLoaded(family);

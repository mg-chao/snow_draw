import 'package:snow_draw_flutter_backend/services/font/flutter_system_font_service.dart';

const FlutterSystemFontService _service = FlutterSystemFontService.instance;

Future<List<String>> loadSystemFontFamilies() => _service.listFamilies();

Future<void> ensureSystemFontLoaded(String family) =>
    _service.ensureLoaded(family);

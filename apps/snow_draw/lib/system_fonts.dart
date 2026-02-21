import 'package:snow_draw_core/draw/services/font/system_font_service.dart';

const SystemFontService _service = SystemFontService.instance;

Future<List<String>> loadSystemFontFamilies() => _service.listFamilies();

Future<void> ensureSystemFontLoaded(String family) =>
    _service.ensureLoaded(family);

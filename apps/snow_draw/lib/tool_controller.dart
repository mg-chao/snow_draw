import 'package:flutter/foundation.dart';

enum ToolType {
  selection,
  rectangle,
  arrow,
  line,
  freeDraw,
  eraser,
  highlight,
  text,
  serialNumber,
  filter,
  watermark,
}

class ToolController extends ValueNotifier<ToolType> {
  ToolController([super.value = ToolType.selection]);

  void setTool(ToolType tool) {
    if (value != tool) {
      value = tool;
    }
  }
}

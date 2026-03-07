import '../../../models/element_state.dart';
import 'serial_number_data.dart';

/// Returns the highest serial number found in [elements].
///
/// Returns `null` when no serial-number elements are present.
int? resolveMaxSerialNumber(Iterable<ElementState> elements) {
  int? maxNumber;
  for (final element in elements) {
    if (element.data case SerialNumberData(:final number)) {
      if (maxNumber == null || number > maxNumber) {
        maxNumber = number;
      }
    }
  }
  return maxNumber;
}

/// Returns the next serial number value that should be assigned.
///
/// Returns `null` when no serial-number elements are present.
int? resolveNextSerialNumber(Iterable<ElementState> elements) {
  final maxNumber = resolveMaxSerialNumber(elements);
  if (maxNumber == null) {
    return null;
  }
  return maxNumber + 1;
}

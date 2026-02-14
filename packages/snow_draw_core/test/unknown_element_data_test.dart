import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/unknown_element_data.dart';

void main() {
  group('UnknownElementData', () {
    test('captures an immutable deep snapshot of rawData', () {
      final source = <String, dynamic>{
        'nested': <String, dynamic>{'value': 1},
        'list': <dynamic>[1, 2],
      };

      final data = UnknownElementData(
        originalType: 'legacy_shape',
        rawData: source,
      );

      (source['nested'] as Map<String, dynamic>)['value'] = 2;
      (source['list'] as List<dynamic>).add(3);

      expect((data.rawData['nested'] as Map<String, dynamic>)['value'], 1);
      expect(data.rawData['list'], equals([1, 2]));
      expect(
        () => (data.rawData['nested'] as Map<String, dynamic>)['value'] = 9,
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => (data.rawData['list'] as List<dynamic>).add(4),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('toJson returns a deep copy detached from internal state', () {
      final data = UnknownElementData(
        originalType: 'legacy_shape',
        rawData: const {
          'nested': {'value': 1},
          'list': [1, 2],
        },
      );

      final json = data.toJson();
      (json['nested'] as Map<String, dynamic>)['value'] = 3;
      (json['list'] as List<dynamic>).add(99);

      expect((data.rawData['nested'] as Map<String, dynamic>)['value'], 1);
      expect(data.rawData['list'], equals([1, 2]));
    });

    test('uses deep equality and stable hash regardless of map order', () {
      final first = UnknownElementData(
        originalType: 'legacy_shape',
        rawData: const {
          'a': 1,
          'nested': {
            'x': 10,
            'y': [1, 2],
          },
        },
      );

      final second = UnknownElementData(
        originalType: 'legacy_shape',
        rawData: const {
          'nested': {
            'y': [1, 2],
            'x': 10,
          },
          'a': 1,
        },
      );

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
    });
  });
}

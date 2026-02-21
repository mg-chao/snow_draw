import 'package:test/test.dart';
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

    test(
      'supports deep freeze and clone for nested maps with non-string keys',
      () {
        final source = <String, dynamic>{
          'map': <Object?, Object?>{
            1: <Object?, Object?>{'inner': 2},
          },
          'list': <dynamic>[
            <Object?, Object?>{'k': 1},
          ],
        };

        final data = UnknownElementData(
          originalType: 'legacy_shape',
          rawData: source,
        );

        ((source['map']! as Map<Object?, Object?>)[1]!
                as Map<Object?, Object?>)['inner'] =
            99;
        ((source['list']! as List<dynamic>).first
                as Map<Object?, Object?>)['k'] =
            7;

        final frozenMap = data.rawData['map']! as Map<Object?, Object?>;
        final frozenInner = frozenMap[1]! as Map<Object?, Object?>;
        expect(frozenInner['inner'], 2);
        expect(
          () => frozenInner['inner'] = 3,
          throwsA(isA<UnsupportedError>()),
        );

        final json = data.toJson();
        final jsonMap = json['map']! as Map<Object?, Object?>;
        final jsonInner = jsonMap[1]! as Map<Object?, Object?>;
        jsonInner['inner'] = 5;
        expect((frozenMap[1]! as Map<Object?, Object?>)['inner'], 2);

        final jsonList = json['list'] as List<dynamic>;
        (jsonList.first as Map<Object?, Object?>)['k'] = 8;
        expect(
          ((data.rawData['list']! as List<dynamic>).first
              as Map<Object?, Object?>)['k'],
          1,
        );
      },
    );

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

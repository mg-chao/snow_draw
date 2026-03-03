import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart';
import 'package:test/test.dart';

void main() {
  test('protocol manifest marks is-fixed-point as no shape validation', () {
    final manifest = getArrowProtocolManifest();
    final entry = manifest.operations.firstWhere(
      (operation) => operation.type == 'is-fixed-point',
    );
    expect(entry.usesShapeValidation, isFalse);
  });

  test('safe protocol rejects malformed nested input as invalid-request', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'bind-point-to-outline',
      'input': <String, dynamic>{
        'arrow': <String, dynamic>{'id': 'arrow-1', 'points': <Object?>[]},
        'bindable': <String, dynamic>{'id': 'bind-1'},
        'edge': 'start',
      },
    });

    expect(response['type'], 'error');
    final error = response['error'] as Map<String, dynamic>;
    expect(error['code'], 'invalid-request');
  });

  test('update-bound-point returns null when binding is null', () {
    final arrow = ArrowState(
      id: 'arrow-1',
      x: 0,
      y: 0,
      width: 100,
      height: 0,
      points: const <Point>[
        <double>[0, 0],
        <double>[100, 0],
      ],
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: null,
      elbowed: false,
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    );
    final bindable = BindableState(
      id: 'bind-1',
      shape: 'rectangle',
      x: 0,
      y: -20,
      width: 100,
      height: 40,
      angle: 0,
      strokeWidth: 1,
      roundness: null,
      zIndex: null,
      backgroundOpaque: true,
      bindingEnabled: true,
      interiorHitEnabled: true,
      visibilityBounds: null,
    );

    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'update-bound-point',
      'input': <String, dynamic>{
        'arrow': arrow,
        'edge': 'start',
        'binding': null,
        'bindable': bindable,
        'bindables': <BindableState>[bindable],
      },
    });

    expect(response['type'], 'optional-point');
    expect(response['point'], isNull);
  });

  test('heading fallback uses point -> otherPoint direction when unbound', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'get-heading-for-elbow-snap',
      'input': <String, dynamic>{
        'point': const <double>[0, 0],
        'otherPoint': const <double>[10, 0],
        'bindable': null,
      },
    });

    expect(response['type'], 'heading');
    expect(response['heading'], 'right');
  });

  test('protocol exports core constants and engine context as plain maps', () {
    final constantsResponse = executeArrowOperationSafe(<String, dynamic>{
      'type': 'get-core-constants',
      'input': null,
    });
    final contextResponse = executeArrowOperationSafe(<String, dynamic>{
      'type': 'get-default-engine-context',
      'input': null,
    });

    expect(constantsResponse['type'], 'core-constants');
    expect(constantsResponse['constants'], isA<Map<String, dynamic>>());
    final constants = constantsResponse['constants'] as Map<String, dynamic>;
    expect(constants['baseBindingGap'], isA<double>());
    expect(constants['basePadding'], isA<double>());

    expect(contextResponse['type'], 'engine-context');
    expect(contextResponse['context'], isA<Map<String, dynamic>>());
    final context = contextResponse['context'] as Map<String, dynamic>;
    expect(context['zoom'], isA<double>());
    expect(context['bindMode'], isA<String>());
  });

  test('validation report operation returns serializable map report', () {
    final arrow = ArrowState(
      id: 'arrow-validate-1',
      x: 0,
      y: 0,
      width: 100,
      height: 0,
      points: const <Point>[
        <double>[0, 0],
        <double>[100, 0],
      ],
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: null,
      elbowed: false,
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    );

    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'validate-arrow-invariant',
      'input': <String, dynamic>{'arrow': arrow},
    });

    expect(response['type'], 'validation-report');
    expect(response['report'], isA<Map<String, dynamic>>());
    final report = response['report'] as Map<String, dynamic>;
    expect(report['valid'], isA<bool>());
    expect(report['violations'], isA<List<String>>());
  });

  test('update-elbow-arrow renormalization carries TS metadata fields', () {
    final arrow = ArrowState(
      id: 'arrow-elbow-1',
      x: 10,
      y: 20,
      width: 100,
      height: 100,
      points: const <Point>[
        <double>[0, 0],
        <double>[40, 0],
        <double>[40, 60],
      ],
      startBinding: null,
      endBinding: null,
      startArrowhead: null,
      endArrowhead: null,
      elbowed: true,
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    );
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'update-elbow-arrow',
      'input': <String, dynamic>{
        'arrow': arrow,
        'updates': <String, dynamic>{},
        'bindables': const <BindableState>[],
        'context': const <String, dynamic>{},
      },
    });

    expect(response['type'], 'arrow-patch');
    final patch = response['patch'] as Map<String, dynamic>;
    expect(patch.containsKey('fixedSegments'), isTrue);
    expect(patch.containsKey('startIsSpecial'), isTrue);
    expect(patch.containsKey('endIsSpecial'), isTrue);
  });

  test(
    'update-elbow-arrow invariant check rejects invalid point array length',
    () {
      final arrow = ArrowState(
        id: 'arrow-elbow-2',
        x: 0,
        y: 0,
        width: 80,
        height: 80,
        points: const <Point>[
          <double>[0, 0],
          <double>[20, 0],
          <double>[20, 20],
          <double>[40, 20],
        ],
        startBinding: null,
        endBinding: null,
        startArrowhead: null,
        endArrowhead: null,
        elbowed: true,
        fixedSegments: null,
        startIsSpecial: null,
        endIsSpecial: null,
      );
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'update-elbow-arrow',
        'input': <String, dynamic>{
          'arrow': arrow,
          'updates': <String, dynamic>{
            'points': const <Point>[
              <double>[0, 0],
            ],
          },
          'bindables': const <BindableState>[],
          'context': const <String, dynamic>{},
          'options': <String, dynamic>{'validateInvariants': true},
        },
      });

      expect(response['type'], 'error');
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], 'operation-failed');
      expect(
        (error['message'] as String).contains('Updated point array length'),
        isTrue,
      );
    },
  );
}

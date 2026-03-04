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

  test(
    'safe protocol rejects bindable payload missing shape/strokeWidth fields',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'is-point-in-bindable',
        'input': <String, dynamic>{
          'point': const <double>[0, 0],
          'bindable': <String, dynamic>{
            'id': 'bind-1',
            'x': 0,
            'y': 0,
            'width': 100,
            'height': 40,
            'angle': 0,
          },
        },
      });

      expect(response['type'], 'error');
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], 'invalid-request');
      final message = error['message'] as String;
      expect(message.contains('request.input.bindable.shape'), isTrue);
      expect(message.contains('request.input.bindable.strokeWidth'), isTrue);
    },
  );

  test('safe protocol rejects arrow payload missing required arrow fields', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'validate-arrow-invariant',
      'input': <String, dynamic>{
        'arrow': <String, dynamic>{
          'id': 'arrow-1',
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 0,
          'points': const <Point>[
            <double>[0, 0],
            <double>[100, 0],
          ],
          'angle': 0,
        },
      },
    });

    expect(response['type'], 'error');
    final error = response['error'] as Map<String, dynamic>;
    expect(error['code'], 'invalid-request');
    final message = error['message'] as String;
    expect(
      message.contains('request.input.arrow.startArrowhead is required'),
      isTrue,
    );
    expect(
      message.contains('request.input.arrow.elbowed must be a boolean'),
      isTrue,
    );
  });

  test('avoid-rectangular-corner accepts elbow-only arrow payload shape', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'avoid-rectangular-corner',
      'input': <String, dynamic>{
        'arrow': <String, dynamic>{'elbowed': false},
        'bindable': <String, dynamic>{
          'id': 'bind-1',
          'shape': 'rectangle',
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 40,
          'angle': 0,
          'strokeWidth': 1,
        },
        'point': const <double>[120, 20],
      },
    });

    expect(response['type'], 'point');
    expect(response['point'], isA<List<double>>());
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

  test(
    'safe protocol rejects point tuples whose length is not exactly two',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'normalize-fixed-point',
        'input': <String, dynamic>{
          'point': const <double>[1, 2, 3],
        },
      });

      expect(response['type'], 'error');
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], 'invalid-request');
      expect(
        (error['message'] as String).contains(
          'request.input.point must be a [number, number] tuple',
        ),
        isTrue,
      );
    },
  );

  test('safe protocol rejects aabb tuples whose length is not exactly four', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'get-heading-for-elbow-snap',
      'input': <String, dynamic>{
        'point': const <double>[0, 0],
        'otherPoint': const <double>[10, 0],
        'bindable': null,
        'aabb': const <double>[0, 0, 100, 100, 999],
      },
    });

    expect(response['type'], 'error');
    final error = response['error'] as Map<String, dynamic>;
    expect(error['code'], 'invalid-request');
    expect(
      (error['message'] as String).contains(
        'request.input.aabb must be null or a [number, number, number, number] tuple',
      ),
      isTrue,
    );
  });

  test(
    'safe protocol rejects apply-arrow-binding-state-patch without patch id',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'apply-arrow-binding-state-patch',
        'input': <String, dynamic>{
          'arrow': <String, dynamic>{
            'id': 'arrow-patch-1',
            'startBinding': null,
            'endBinding': null,
          },
          'patch': <String, dynamic>{},
        },
      });

      expect(response['type'], 'error');
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], 'invalid-request');
      expect(
        (error['message'] as String).contains(
          'request.input.patch.id must be a string',
        ),
        isTrue,
      );
    },
  );

  test(
    'safe protocol rejects apply-arrow-binding-state-patches when patch id is missing',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'apply-arrow-binding-state-patches',
        'input': <String, dynamic>{
          'arrows': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'arrow-patches-1',
              'startBinding': null,
              'endBinding': null,
            },
          ],
          'patches': <Map<String, dynamic>>[<String, dynamic>{}],
        },
      });

      expect(response['type'], 'error');
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], 'invalid-request');
      expect(
        (error['message'] as String).contains(
          'request.input.patches[0].id must be a string',
        ),
        isTrue,
      );
    },
  );

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
        'context': const <String, dynamic>{
          'zoom': 1,
          'isBindingEnabled': true,
          'bindMode': 'inside',
          'maxCoordinate': 10000,
        },
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
          'context': const <String, dynamic>{
            'zoom': 1,
            'isBindingEnabled': true,
            'bindMode': 'inside',
            'maxCoordinate': 10000,
          },
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

  test(
    'finalize-focus-point-drag requires ArrowBindingState arrow payload',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'finalize-focus-point-drag',
        'input': <String, dynamic>{
          'arrow': <String, dynamic>{'id': 'arrow-1'},
          'bindables': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'bind-1', 'boundArrowIds': <String>[]},
          ],
        },
      });

      expect(response['type'], 'error');
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], 'invalid-request');
      expect(
        (error['message'] as String).contains(
          'request.input.arrow.startBinding is required',
        ),
        isTrue,
      );
    },
  );

  test('apply-arrow-patch rejects invalid patch.points tuples', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'apply-arrow-patch',
      'input': <String, dynamic>{
        'arrow': <String, dynamic>{
          'id': 'arrow-1',
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 0,
          'points': const <Point>[
            <double>[0, 0],
            <double>[100, 0],
          ],
          'startBinding': null,
          'endBinding': null,
          'startArrowhead': null,
          'endArrowhead': null,
          'elbowed': false,
          'fixedSegments': null,
          'startIsSpecial': null,
          'endIsSpecial': null,
        },
        'patch': <String, dynamic>{
          'points': const <dynamic>[
            <double>[0, 0],
            <double>[50, 0, 1],
          ],
        },
      },
    });

    expect(response['type'], 'error');
    final error = response['error'] as Map<String, dynamic>;
    expect(error['code'], 'invalid-request');
    expect(
      (error['message'] as String).contains(
        'request.input.patch.points must be an array of points when provided',
      ),
      isTrue,
    );
  });

  test('bind-point-to-outline rejects null customIntersector', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'bind-point-to-outline',
      'input': <String, dynamic>{
        'arrow': <String, dynamic>{
          'id': 'arrow-1',
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 0,
          'points': const <Point>[
            <double>[0, 0],
            <double>[100, 0],
          ],
          'startBinding': null,
          'endBinding': null,
          'startArrowhead': null,
          'endArrowhead': null,
          'elbowed': false,
          'fixedSegments': null,
          'startIsSpecial': null,
          'endIsSpecial': null,
        },
        'bindable': <String, dynamic>{
          'id': 'bind-1',
          'shape': 'rectangle',
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 40,
          'angle': 0,
          'strokeWidth': 1,
        },
        'edge': 'start',
        'customIntersector': null,
      },
    });

    expect(response['type'], 'error');
    final error = response['error'] as Map<String, dynamic>;
    expect(error['code'], 'invalid-request');
    expect(
      (error['message'] as String).contains(
        'request.input.customIntersector must be a tuple of two points',
      ),
      isTrue,
    );
  });

  test(
    'max-binding-distance ignores unrelated malformed fields by operation scope',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'max-binding-distance',
        'input': <String, dynamic>{
          'zoom': 1,
          'bindable': <String, dynamic>{'id': 'ignored-invalid-bindable'},
        },
      });

      expect(response['type'], 'number');
      expect(response['value'], isA<double>());
    },
  );

  test(
    'remap-arrow-bindings-after-duplication validates preserveUnmapped type',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'remap-arrow-bindings-after-duplication',
        'input': <String, dynamic>{
          'arrows': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'arrow-1',
              'startBinding': null,
              'endBinding': null,
            },
          ],
          'bindableIdMap': <String, String>{'a': 'b'},
          'preserveUnmapped': 'yes',
        },
      });

      expect(response['type'], 'error');
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], 'invalid-request');
      expect(
        (error['message'] as String).contains(
          'request.input.preserveUnmapped must be a boolean',
        ),
        isTrue,
      );
    },
  );

  test(
    'finalize-focus-point-drag reconciles relation bindable patches from map payloads',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'finalize-focus-point-drag',
        'input': <String, dynamic>{
          'arrow': <String, dynamic>{
            'id': 'arrow-1',
            'startBinding': null,
            'endBinding': null,
          },
          'bindables': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'bind-1',
              'boundArrowIds': <String>['arrow-1'],
            },
          ],
        },
      });

      expect(response['type'], 'engine-result');
      final result = response['result'] as EngineResult;
      expect(result.bindablePatches, hasLength(1));
      final patch = result.bindablePatches.first;
      expect(patch.id, 'bind-1');
      expect(patch.removeBoundArrowId, 'arrow-1');
      expect(patch.addBoundArrowId, isNull);
    },
  );

  test('move-fixed-segment-to-point accepts map arrow payload', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'move-fixed-segment-to-point',
      'input': <String, dynamic>{
        'arrow': <String, dynamic>{
          'id': 'arrow-1',
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 0,
          'points': const <Point>[
            <double>[0, 0],
            <double>[100, 0],
          ],
          'startBinding': null,
          'endBinding': null,
          'startArrowhead': null,
          'endArrowhead': null,
          'elbowed': false,
          'fixedSegments': null,
          'startIsSpecial': null,
          'endIsSpecial': null,
        },
        'segmentIndex': 1,
        'pointer': const <double>[100, 0],
      },
    });

    expect(response['type'], 'fixed-segment-drag');
    final value = response['value'] as MoveFixedSegmentToPointResult;
    expect(value.activeSegmentIndex, 1);
    expect(value.activeSegmentMidPoint, const <double>[50, 0]);
  });

  test(
    'derive-bindable-patches-for-binding-change accepts previous/next without id',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'derive-bindable-patches-for-binding-change',
        'input': <String, dynamic>{
          'arrowId': 'arrow-1',
          'previous': <String, dynamic>{
            'startBinding': null,
            'endBinding': null,
          },
          'next': <String, dynamic>{'startBinding': null, 'endBinding': null},
        },
      });

      expect(response['type'], 'bindable-patches');
      expect(response['patches'], isA<List<BindablePatch>>());
      expect(response['patches'], isEmpty);
    },
  );

  test('sync-bindings-after-duplication accepts map arrays', () {
    final response = executeArrowOperationSafe(<String, dynamic>{
      'type': 'sync-bindings-after-duplication',
      'input': <String, dynamic>{
        'arrows': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'arrow-1',
            'x': 0,
            'y': 0,
            'width': 100,
            'height': 0,
            'points': const <Point>[
              <double>[0, 0],
              <double>[100, 0],
            ],
            'startBinding': null,
            'endBinding': null,
            'startArrowhead': null,
            'endArrowhead': null,
            'elbowed': false,
            'fixedSegments': null,
            'startIsSpecial': null,
            'endIsSpecial': null,
          },
        ],
        'bindables': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'bind-1',
            'boundArrowIds': <String>['arrow-1'],
          },
        ],
        'bindableIdMap': <String, String>{'bind-1': 'bind-2'},
        'arrowIdMap': <String, String>{'arrow-1': 'arrow-2'},
      },
    });

    expect(response['type'], 'binding-lifecycle-sync');
    final value = response['value'] as LifecycleSyncResult;
    expect(value.arrows, hasLength(1));
    expect(value.bindables, hasLength(1));
    expect(value.bindables.first.boundArrowIds, const <String>['arrow-2']);
  });

  test(
    'generate-elbow-arrow-path formats integer coordinates without trailing decimals',
    () {
      final response = executeArrowOperationSafe(<String, dynamic>{
        'type': 'generate-elbow-arrow-path',
        'input': <String, dynamic>{
          'points': const <Point>[
            <double>[0, 0],
            <double>[100, 0],
            <double>[100, 40],
          ],
          'radius': 8,
        },
      });

      expect(response['type'], 'string');
      expect(response['value'], 'M 0 0 L 92 0 Q 100 0, 100 8 L 100 40');
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

void main() {
  group('resolveInteractionDynamicSceneFromCachedKey', () {
    test('uses optimized preview resolver when cached optimized ids exist', () {
      final stateView = _buildStateView();
      final cachedMetadata = _buildCachedMetadata(
        optimizedDynamicElementIds: const {'rect'},
        optimizedSceneHasPotentialOccluders: true,
        isHighlightMaskVisible: true,
        isWatermarkVisible: true,
      );
      var optimizedResolverCalled = false;
      var previewResolverCalled = false;
      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        cachedMetadata: cachedMetadata,
        resolvePreviewElements: (view) {
          previewResolverCalled = true;
          return const <String, ElementState>{};
        },
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) {
          optimizedResolverCalled = true;
          expect(
            optimizedElementIds,
            cachedMetadata.optimizedDynamicElementIds,
          );
          return {'rect': _rectangle(id: 'rect')};
        },
        resolveDynamicPreviewElementIds: (view, previewElementsById) {
          expect(previewElementsById.keys, contains('rect'));
          return {'rect'};
        },
      );

      expect(optimizedResolverCalled, isTrue);
      expect(previewResolverCalled, isFalse);
      expect(scene.previewElementsById.keys, contains('rect'));
      expect(scene.dynamicPreviewElementIds, {'rect'});
      expect(scene.optimizedDynamicElementIds, {'rect'});
      expect(scene.optimizedSceneHasPotentialOccluders, isTrue);
      expect(scene.isHighlightMaskVisible, isTrue);
      expect(scene.isWatermarkVisible, isTrue);
    });

    test('uses preview resolver when no optimized ids exist', () {
      final stateView = _buildStateView();
      final cachedMetadata = _buildCachedMetadata(
        optimizedDynamicElementIds: const <String>{},
        isHighlightMaskVisible: true,
        isWatermarkVisible: true,
      );
      var optimizedResolverCalled = false;
      var previewResolverCalled = false;
      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        cachedMetadata: cachedMetadata,
        resolvePreviewElements: (view) {
          previewResolverCalled = true;
          return {'rect': _rectangle(id: 'rect')};
        },
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) {
          optimizedResolverCalled = true;
          return const <String, ElementState>{};
        },
        resolveDynamicPreviewElementIds: (view, previewElementsById) =>
            previewElementsById.keys.toSet(),
      );

      expect(previewResolverCalled, isTrue);
      expect(optimizedResolverCalled, isFalse);
      expect(scene.previewElementsById.keys, contains('rect'));
      expect(scene.dynamicPreviewElementIds, {'rect'});
      expect(scene.optimizedDynamicElementIds, isEmpty);
      expect(scene.optimizedSceneHasPotentialOccluders, isFalse);
      expect(scene.isHighlightMaskVisible, isTrue);
      expect(scene.isWatermarkVisible, isTrue);
    });

    test('clears occluder hint when optimized ids are empty', () {
      final stateView = _buildStateView();
      final cachedMetadata = _buildCachedMetadata(
        optimizedDynamicElementIds: const <String>{},
        optimizedSceneHasPotentialOccluders: true,
        isHighlightMaskVisible: true,
      );

      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        cachedMetadata: cachedMetadata,
        resolvePreviewElements: (view) => const <String, ElementState>{},
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) =>
            const <String, ElementState>{},
        resolveDynamicPreviewElementIds: (view, previewElementsById) =>
            const <String>{},
      );

      expect(scene.optimizedDynamicElementIds, isEmpty);
      expect(scene.optimizedSceneHasPotentialOccluders, isFalse);
    });

    test('returns immutable snapshot collections', () {
      final stateView = _buildStateView();
      final cachedMetadata = _buildCachedMetadata(
        optimizedDynamicElementIds: const {'rect'},
        optimizedSceneHasPotentialOccluders: true,
        isHighlightMaskVisible: true,
      );
      final mutablePreviewElements = <String, ElementState>{
        'rect': _rectangle(id: 'rect'),
      };
      final mutableDynamicIds = <String>{'rect'};
      final scene = resolveInteractionDynamicSceneFromCachedKey(
        stateView: stateView,
        cachedMetadata: cachedMetadata,
        resolvePreviewElements: (view) => mutablePreviewElements,
        resolvePreviewByOptimizedIds: (view, optimizedElementIds) =>
            mutablePreviewElements,
        resolveDynamicPreviewElementIds: (view, previewElementsById) =>
            mutableDynamicIds,
      );

      mutablePreviewElements['next'] = _rectangle(id: 'next');
      mutableDynamicIds.add('next');

      expect(scene.previewElementsById.keys, isNot(contains('next')));
      expect(scene.dynamicPreviewElementIds, isNot(contains('next')));
      expect(
        () => scene.previewElementsById['third'] = _rectangle(id: 'third'),
        throwsUnsupportedError,
      );
      expect(
        () => scene.dynamicPreviewElementIds.add('third'),
        throwsUnsupportedError,
      );
      expect(
        () => scene.optimizedDynamicElementIds.add('third'),
        throwsUnsupportedError,
      );
    });
  });
}

DrawStateView _buildStateView() {
  final state = DrawState(
    domain: DomainState(
      document: DocumentState(elements: const [_seedRectangle]),
    ),
  );
  return DrawStateView.withPreview(
    state: state,
    previewElementsById: const {},
    effectiveSelection: EffectiveSelection.none,
    snapGuides: const [],
  );
}

CachedInteractionDynamicMetadata _buildCachedMetadata({
  required Set<String> optimizedDynamicElementIds,
  required bool isHighlightMaskVisible,
  bool isWatermarkVisible = false,
  bool optimizedSceneHasPotentialOccluders = false,
}) => CachedInteractionDynamicMetadata(
  optimizedDynamicElementIds: optimizedDynamicElementIds,
  optimizedSceneHasPotentialOccluders: optimizedSceneHasPotentialOccluders,
  isHighlightMaskVisible: isHighlightMaskVisible,
  highlightMaskConfig: const HighlightMaskConfig(),
  isWatermarkVisible: isWatermarkVisible,
  watermarkConfig: const WatermarkConfig(),
);

ElementState _rectangle({required String id}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 10, maxY: 10),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);

const _seedRectangle = ElementState(
  id: 'seed',
  rect: DrawRect(maxX: 10, maxY: 10),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

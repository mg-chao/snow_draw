import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/main.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';

void main() {
  testWidgets('MyApp builds', (tester) async {
    initializePropertyRegistry();
    final context = createAppContext();
    final store = DefaultDrawStore(
      context: context,
      includeSelectionInHistory: true,
    );

    await tester.pumpWidget(MyApp(context: context, storeOverride: store));
    await tester.pump();

    expect(find.byType(MyApp), findsOneWidget);

    store.dispose();
  });
}

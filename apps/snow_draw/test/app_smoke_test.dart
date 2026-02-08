import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/main.dart';
import 'package:snow_draw/property_initialization.dart';

void main() {
  testWidgets('MyApp builds', (tester) async {
    initializePropertyRegistry();
    final context = createAppContext();

    await tester.pumpWidget(MyApp(context: context));
    await tester.pump();

    expect(find.byType(MyApp), findsOneWidget);
  });
}

import 'package:b1gtv/screens/start_problem.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a failed start shows the reason and Try again, not only the logo', (tester) async {
    var retried = 0;
    await tester.pumpWidget(StartProblemApp(
      error: 'PlatformException(PlatformException, java.lang.NoSuchMethodError: no non-static method getAll)',
      retry: () => retried++,
    ));
    // The version check finds no website in tests and ends at once.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('could not open'), findsOneWidget);
    expect(find.textContaining('NoSuchMethodError'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Update now'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(retried, 1);
  });
}

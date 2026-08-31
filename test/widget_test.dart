// Placeholder test. The previous version was unmodified Flutter
// counter-app boilerplate that pumped a `MyApp` widget — this app has
// never had one; its real entry point is `ViyoApp` in lib/main.dart.
// That made both `flutter test` and `flutter analyze` fail for reasons
// with nothing to do with the app itself.
//
// A real widget test for ViyoApp needs Supabase mocked out first (its
// SplashScreen reads SupabaseService.currentUserId on init), which is
// a separate piece of work. This just keeps the test suite valid in
// the meantime.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder — replace with real widget/unit tests', () {
    expect(1 + 1, 2);
  });
}

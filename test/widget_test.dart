import 'package:flutter_test/flutter_test.dart';

import 'package:takvim_takip/main.dart';

void main() {
  testWidgets('Uygulama açılır ve başlığı gösterir', (tester) async {
    await tester.pumpWidget(const TakvimTakipApp());

    expect(find.text('Takvim Takip'), findsOneWidget);
  });
}

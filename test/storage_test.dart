import 'package:button_panic/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Endless best only goes up', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ScoreStore.open();
    expect(await store.recordEndless(10), isTrue);
    expect(await store.recordEndless(4), isFalse);
    expect(store.bestEndless, 10);
  });

  test('Daily keeps the first score of the day and the best', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ScoreStore.open();
    final day = DateTime(2026, 10, 15, 9);
    await store.recordDaily(day, 7);
    await store.recordDaily(day, 12);
    final r = await store.recordDaily(day, 3);
    expect(r.firstScore, 7);
    expect(r.bestScore, 12);
    expect(store.dailyFor(DateTime(2026, 10, 16)), isNull, reason: 'a new day starts fresh');
  });
}

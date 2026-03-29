/// Simple app-wide clock abstraction.
///
/// By default, the app uses the real device time.
/// If you need a demo mode for UI testing, you can temporarily enable
/// [_useSimulatedTime] below.
class AppClock {
  AppClock._();

  static final AppClock instance = AppClock._();

  DateTime? _realStart;
  DateTime? _simStart;

  DateTime now() {
    if (!_useSimulatedTime) return DateTime.now();

    final realStart = _realStart ??= DateTime.now();
    final simStart = _simStart ??= DateTime(
      realStart.year,
      realStart.month,
      realStart.day,
      13,
      30,
    );

    final elapsed = DateTime.now().difference(realStart);
    return simStart.add(elapsed);
  }

  static const bool _useSimulatedTime = false;
}

DateTime appNow() => AppClock.instance.now();

abstract class UlinqLogger {
  const UlinqLogger();

  void debug(String message);
  void info(String message);
  void warn(String message);
  void error(String message, {Object? error, StackTrace? stackTrace});
}

class UlinqNoopLogger extends UlinqLogger {
  const UlinqNoopLogger();

  @override
  void debug(String message) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}
}

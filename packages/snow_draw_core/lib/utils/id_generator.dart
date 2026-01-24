import 'dart:math';

/// ID generator function.
typedef IdGenerator = String Function();

/// Random-string based ID generator.
class RandomStringIdGenerator {
  RandomStringIdGenerator({
    int length = 16,
    String chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
    Random? random,
  }) : _length = length,
       _chars = chars,
       _random = random ?? Random();
  final Random _random;
  final int _length;
  final String _chars;

  String call() {
    final randomString = String.fromCharCodes(
      Iterable.generate(
        _length,
        (_) => _chars.codeUnitAt(_random.nextInt(_chars.length)),
      ),
    );
    return randomString;
  }
}

/// Predictable ID generator (useful for tests).
class SequentialIdGenerator {
  SequentialIdGenerator({String prefix = 'id', int startFrom = 1})
    : _prefix = prefix,
      _counter = startFrom;
  final String _prefix;
  int _counter;

  String call() => '$_prefix-${_counter++}';
}

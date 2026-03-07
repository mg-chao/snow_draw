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

  String call() => String.fromCharCodes(
    Iterable.generate(
      _length,
      (_) => _chars.codeUnitAt(_random.nextInt(_chars.length)),
    ),
  );
}

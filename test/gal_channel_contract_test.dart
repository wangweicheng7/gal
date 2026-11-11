import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal_ohos/gal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'hasAccess' || 'requestAccess' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('image bytes preserve the standard Gal channel payload', () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71]);
    await Gal.putImageBytes(bytes, name: 'pawrio-poster');
    expect(
        calls.map((call) => call.method), ['requestAccess', 'putImageBytes']);
    expect(calls.first.arguments, {'toAlbum': false});
    expect(calls.last.arguments, {
      'bytes': bytes,
      'album': null,
      'name': 'pawrio-poster',
    });
  });

  test('image paths use the same public save protocol', () async {
    await Gal.putImage('/sandbox/poster.png');
    expect(calls.last.method, 'putImage');
    expect(
        calls.last.arguments, {'path': '/sandbox/poster.png', 'album': null});
  });

  test('video paths use the same public save protocol', () async {
    await Gal.putVideo('/sandbox/replay.mp4');
    expect(calls.last.method, 'putVideo');
    expect(
        calls.last.arguments, {'path': '/sandbox/replay.mp4', 'album': null});
  });

  test('public-save access checks retain the toAlbum parameter', () async {
    expect(await Gal.hasAccess(), isTrue);
    expect(await Gal.requestAccess(), isTrue);
    expect(calls.map((call) => call.method), ['hasAccess', 'requestAccess']);
    expect(calls.map((call) => call.arguments), [
      {'toAlbum': false},
      {'toAlbum': false},
    ]);
  });

  test('system save cancellation maps to accessDenied', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestAccess') return true;
      throw PlatformException(
          code: 'ACCESS_DENIED', message: 'Save cancelled.');
    });
    await expectLater(
      Gal.putImage('/sandbox/poster.png'),
      throwsA(isA<GalException>().having(
        (error) => error.type,
        'type',
        GalExceptionType.accessDenied,
      )),
    );
  });

  test('unsupported album is explicit and is not a format error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestAccess') return false;
      throw PlatformException(
        code: 'UNEXPECTED',
        message: 'Custom albums are not supported.',
      );
    });
    await expectLater(
      Gal.putImage('/sandbox/poster.png', album: 'Pawrio'),
      throwsA(isA<GalException>()
          .having((error) => error.type, 'type', GalExceptionType.unexpected)
          .having((error) => error.platformException.message, 'message',
              contains('Custom albums'))),
    );
  });

  test('storage failure preserves the standard Gal error code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestAccess') return true;
      throw PlatformException(code: 'NOT_ENOUGH_SPACE');
    });
    await expectLater(
      Gal.putVideo('/sandbox/replay.mp4'),
      throwsA(isA<GalException>().having(
        (error) => error.type,
        'type',
        GalExceptionType.notEnoughSpace,
      )),
    );
  });

  test('open forwards a platform handler error as unexpected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
          code: 'UNEXPECTED', message: 'No gallery handler.');
    });
    await expectLater(
      Gal.open(),
      throwsA(isA<GalException>().having(
        (error) => error.type,
        'type',
        GalExceptionType.unexpected,
      )),
    );
  });
}

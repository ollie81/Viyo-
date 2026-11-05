import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/services/file_saver_io.dart';

/// A tiny file server that honours HTTP Range and can cut the connection
/// part-way through, like a phone losing signal.
class _Server {
  final List<int> bytes;
  final bool supportsRange;
  int? dropAfter; // bytes to send before dropping, on the next request only
  final List<String?> rangesSeen = [];
  late ServerSocket _sock;

  _Server(this.bytes, {this.supportsRange = true});

  String get url => 'http://127.0.0.1:${_sock.port}/file.mp4';

  Future<void> start() async {
    _sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _sock.listen((client) {
      final buf = <int>[];
      late StreamSubscription<List<int>> sub;
      sub = client.listen((chunk) async {
        buf.addAll(chunk);
        final text = String.fromCharCodes(buf);
        if (!text.contains('\r\n\r\n')) return;
        await sub.cancel();
        final m = RegExp(r'range: bytes=(\d+)-', caseSensitive: false).firstMatch(text);
        rangesSeen.add(m == null ? null : 'bytes=${m.group(1)}-');
        var start = 0;
        var head = 'HTTP/1.1 200 OK\r\n';
        if (supportsRange && m != null) {
          start = int.parse(m.group(1)!);
          if (start >= bytes.length) {
            client.add('HTTP/1.1 416 Range Not Satisfiable\r\ncontent-length: 0\r\nconnection: close\r\n\r\n'.codeUnits);
            await client.flush();
            await client.close();
            return;
          }
          head = 'HTTP/1.1 206 Partial Content\r\ncontent-range: bytes $start-${bytes.length - 1}/${bytes.length}\r\n';
        }
        final body = bytes.sublist(start);
        client.add('${head}content-type: video/mp4\r\ncontent-length: ${body.length}\r\nconnection: close\r\n\r\n'.codeUnits);
        final cut = dropAfter;
        dropAfter = null;
        client.add(cut == null ? body : body.sublist(0, cut));
        await client.flush();
        if (cut != null) {
          client.destroy();
        } else {
          await client.close();
        }
      });
    });
  }

  Future<void> stop() => _sock.close();
}

void main() {
  late Directory dir;
  final rnd = Random(7);
  final data = List<int>.generate(3 * 1024 * 1024 + 17, (_) => rnd.nextInt(256));

  setUp(() async => dir = await Directory.systemTemp.createTemp('viyo_dl_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('downloads the whole file and reports progress', () async {
    final server = _Server(data)..dropAfter = null;
    await server.start();
    final target = File('${dir.path}/ep01.mp4');
    var last = 0;
    final path = await downloadResumable(url: server.url, target: target, onProgress: (got, total) {
      expect(total, data.length);
      last = got;
    });
    expect(await File(path).readAsBytes(), data);
    expect(last, data.length);
    expect(File('${target.path}.part').existsSync(), isFalse);
    await server.stop();
  });

  test('an interrupted download fails safely and the retry resumes from where it stopped', () async {
    final server = _Server(data)..dropAfter = 1024 * 1024;
    await server.start();
    final target = File('${dir.path}/ep02.mp4');
    await expectLater(downloadResumable(url: server.url, target: target), throwsA(anything));
    expect(target.existsSync(), isFalse, reason: 'a half file is never presented as finished');
    final partLen = File('${target.path}.part').lengthSync();
    expect(partLen, greaterThan(0));

    final path = await downloadResumable(url: server.url, target: target);
    expect(server.rangesSeen.last, 'bytes=$partLen-', reason: 'the retry asks only for the missing bytes');
    expect(await File(path).readAsBytes(), data, reason: 'the resumed file is byte-for-byte correct');
    await server.stop();
  });

  test('if the server ignores Range the retry starts over cleanly', () async {
    final server = _Server(data, supportsRange: false)..dropAfter = 500000;
    await server.start();
    final target = File('${dir.path}/ep03.mp4');
    await expectLater(downloadResumable(url: server.url, target: target), throwsA(anything));
    final path = await downloadResumable(url: server.url, target: target);
    expect(await File(path).readAsBytes(), data);
    await server.stop();
  });

  test('a part file that is already complete just finishes', () async {
    final server = _Server(data);
    await server.start();
    final target = File('${dir.path}/ep04.mp4');
    await File('${target.path}.part').writeAsBytes(data);
    final path = await downloadResumable(url: server.url, target: target);
    expect(await File(path).readAsBytes(), data);
    await server.stop();
  });
}

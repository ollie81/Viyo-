import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/services/file_upload_service.dart';

void main() {
  tearDown(FileUploadService.resetForTests);

  test('uploads go through the server only when it says files live on Bunny', () async {
    FileUploadService.resetForTests();
    FileUploadService.fetchStore = () async => 'bunny';
    expect(await FileUploadService.usesServer(), isTrue);

    FileUploadService.resetForTests();
    FileUploadService.fetchStore = () async => 'supabase';
    expect(await FileUploadService.usesServer(), isFalse);
  });

  test('if the server cannot be asked, uploads keep going to Supabase as before', () async {
    FileUploadService.resetForTests();
    FileUploadService.fetchStore = () async => throw Exception('offline');
    expect(await FileUploadService.usesServer(), isFalse);
  });

  test('the answer is remembered instead of asked on every upload', () async {
    FileUploadService.resetForTests();
    var calls = 0;
    FileUploadService.fetchStore = () async {
      calls++;
      return 'bunny';
    };
    await FileUploadService.usesServer();
    await FileUploadService.usesServer();
    expect(calls, 1);
  });
}

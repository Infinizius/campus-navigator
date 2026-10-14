import 'dart:io';

import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager/src/storage/file_system/file_system.dart';
import 'package:path/path.dart' as path;

class TestCacheManager extends CacheManager with ImageCacheManager {
  TestCacheManager._(this.directory, Config config) : super(config);

  final Directory directory;

  static Future<TestCacheManager> create() async {
    final directory = await Directory.systemTemp.createTemp('campus-qa-cache-');
    final key = path.basename(directory.path);
    final config = Config(
      key,
      repo: JsonCacheInfoRepository(
          path: path.join(directory.path, 'cache.json')),
      fileSystem: _TemporaryFileSystem(directory.path),
    );
    final manager = TestCacheManager._(directory, config);
    await manager.getFileFromCache('__cache_ready__');
    return manager;
  }

  Future<void> disposeAndDelete() async {
    await dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _TemporaryFileSystem implements FileSystem {
  _TemporaryFileSystem(this.root);

  final String root;
  final LocalFileSystem _fileSystem = const LocalFileSystem();

  @override
  Future<file.File> createFile(String name) async {
    final directory = _fileSystem.directory(root);
    await directory.create(recursive: true);
    return directory.childFile(name);
  }
}

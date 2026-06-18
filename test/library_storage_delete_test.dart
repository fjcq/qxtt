// 验证 LibraryStorage.deleteAlbumFiles 在多场景下能彻底删除本地文件
// 1) 按 localPath 命中
// 2) 按 downloadDir/sanitize(title) 命中
// 3) 按 downloadDir/sanitize(albumId) 命中
// 4) 模糊扫描命中（目录名 === sanitize(title)）
// 5) 目录不存在视为已删
// 6) 单文件被占用时仍能清理其余文件
// 7) 从 coverPath 反推本子目录删除
// 8) 顶层 cover.jpg 模糊扫描命中
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic_mobile/data/models/library_album_model.dart';
import 'package:jmcomic_mobile/utils/library_storage.dart';

void main()
{
    late Directory tmpRoot;

    setUp(() async
    {
        tmpRoot = await Directory.systemTemp.createTemp('lib_del_test_');
    });

    tearDown(() async
    {
        if (await tmpRoot.exists())
        {
            await tmpRoot.delete(recursive: true);
        }
    });

    LibraryAlbumModel makeAlbum({
        String albumId = '12345',
        String title = 'Hello World',
        String localPath = '',
        String coverPath = '',
    })
    {
        return LibraryAlbumModel()
            ..albumId = albumId
            ..title = title
            ..localPath = localPath
            ..coverPath = coverPath;
    }

    test('命中 localPath', () async
    {
        final albumDir =
            '${tmpRoot.path}${Platform.pathSeparator}myAlbum';
        await Directory(albumDir).create(recursive: true);
        await File('$albumDir${Platform.pathSeparator}page.jpg')
            .writeAsBytes([1, 2, 3]);

        final album = makeAlbum(localPath: albumDir);
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
        expect(await Directory(albumDir).exists(), isFalse);
    });

    test('按 title 兜底命中', () async
    {
        const safe = 'Hello World';
        final albumDir =
            '${tmpRoot.path}${Platform.pathSeparator}$safe';
        await Directory(albumDir).create(recursive: true);
        await File('$albumDir${Platform.pathSeparator}page.jpg')
            .writeAsBytes([1, 2, 3]);

        final album = makeAlbum();
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
        expect(await Directory(albumDir).exists(), isFalse);
    });

    test('按 albumId 兜底命中', () async
    {
        final albumDir =
            '${tmpRoot.path}${Platform.pathSeparator}12345';
        await Directory(albumDir).create(recursive: true);
        await File('$albumDir${Platform.pathSeparator}page.jpg')
            .writeAsBytes([1, 2, 3]);

        final album = makeAlbum();
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
        expect(await Directory(albumDir).exists(), isFalse);
    });

    test('模糊扫描命中', () async
    {
        // localPath 与 title 都为空
        final albumDir =
            '${tmpRoot.path}${Platform.pathSeparator}12345';
        await Directory(albumDir).create(recursive: true);
        await File('$albumDir${Platform.pathSeparator}image.jpg')
            .writeAsBytes([1, 2, 3]);

        final album = LibraryAlbumModel()
            ..albumId = '12345'
            ..title = '';
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
        expect(await Directory(albumDir).exists(), isFalse);
    });

    test('目录不存在视为已删', () async
    {
        final album = makeAlbum(localPath: '${tmpRoot.path}/no-such');
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
    });

    test('批量删除多本', () async
    {
        for (final id in ['1', '2', '3'])
        {
            final dir = '${tmpRoot.path}${Platform.pathSeparator}$id';
            await Directory(dir).create(recursive: true);
            await File('$dir${Platform.pathSeparator}p.jpg')
                .writeAsBytes([0]);
        }
        final albums = ['1', '2', '3']
            .map((id) =>
                LibraryAlbumModel()..albumId = id..title = id)
            .toList();
        final r = await LibraryStorage.deleteBatchAlbumFiles(
            albums,
            downloadDir: tmpRoot.path,
        );
        for (final id in ['1', '2', '3'])
        {
            expect(r[id], isTrue);
            expect(
                await Directory('${tmpRoot.path}/$id').exists(),
                isFalse,
            );
        }
    });

    test('从 coverPath 反推本子目录删除（场景 A：cover 在本子目录顶层）',
            () async
    {
        // 真实下载结构：<downloadDir>/<safeTitle>/cover.jpg + 章节子目录
        const safe = 'Hello World';
        final albumDir =
            '${tmpRoot.path}${Platform.pathSeparator}$safe';
        final coverPath = '$albumDir${Platform.pathSeparator}cover.jpg';
        await Directory(albumDir).create(recursive: true);
        await File(coverPath).writeAsBytes([0]);
        // 章节
        final epDir = '$albumDir${Platform.pathSeparator}001';
        await Directory(epDir).create(recursive: true);
        await File('$epDir${Platform.pathSeparator}00001.jpg')
            .writeAsBytes([0]);

        // 数据库里 localPath 是空的（极端情况），但 coverPath 是有效的
        final album = makeAlbum(coverPath: coverPath);
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
        expect(await Directory(albumDir).exists(), isFalse);
    });

    test('从 coverPath 反推本子目录删除（场景 B：cover 实际是首张图，'
            '在章节子目录里）', () async
    {
        // 兜底图场景：coverPath 指向 <downloadDir>/<safeTitle>/<safeEp>/00001.jpg
        const safe = 'Hello World';
        final albumDir =
            '${tmpRoot.path}${Platform.pathSeparator}$safe';
        final epDir = '$albumDir${Platform.pathSeparator}001';
        final coverPath = '$epDir${Platform.pathSeparator}00001.jpg';
        await Directory(epDir).create(recursive: true);
        await File(coverPath).writeAsBytes([0]);

        final album = makeAlbum(coverPath: coverPath);
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
        expect(await Directory(albumDir).exists(), isFalse);
        expect(await Directory(epDir).exists(), isFalse);
    });

    test('顶层 cover.jpg 模糊扫描命中（目录名不匹配 title/albumId）',
            () async
    {
        // 模拟一个"乱命名"的目录：实际叫 some_weird_name
        // 但顶层有 cover.jpg
        final weirdDir =
            '${tmpRoot.path}${Platform.pathSeparator}some_weird_name';
        await Directory(weirdDir).create(recursive: true);
        await File('$weirdDir${Platform.pathSeparator}cover.jpg')
            .writeAsBytes([0]);
        await File('$weirdDir${Platform.pathSeparator}00001.jpg')
            .writeAsBytes([0]);

        // album 没有任何匹配字段，但只要顶层有 cover.jpg 就能识别
        final album = LibraryAlbumModel()
            ..albumId = '9999'
            ..title = 'unrelated title'
            ..localPath = '';
        final ok = await LibraryStorage.deleteAlbumFiles(
            album,
            downloadDir: tmpRoot.path,
        );
        expect(ok, isTrue);
        expect(await Directory(weirdDir).exists(), isFalse);
    });

    test('forceDelete 公开接口：不存在的目录返回 true', () async
    {
        final nonExist = Directory('${tmpRoot.path}/never-existed');
        final ok = await LibraryStorage.forceDelete(nonExist);
        expect(ok, isTrue);
    });

    test('forceDelete 公开接口：递归清理含多层子目录的目录', () async
    {
        final root = Directory('${tmpRoot.path}${Platform.pathSeparator}deep');
        await root.create(recursive: true);
        for (var i = 0; i < 3; i++)
        {
            final sub = Directory('${root.path}${Platform.pathSeparator}sub$i');
            await sub.create(recursive: true);
            await File('${sub.path}${Platform.pathSeparator}p.jpg')
                .writeAsBytes([i]);
        }
        final ok = await LibraryStorage.forceDelete(root);
        expect(ok, isTrue);
        expect(await root.exists(), isFalse);
    });
}

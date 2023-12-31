import 'dart:convert' show utf8;
import 'dart:io';

import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/file_type.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/native/cache_helper.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('SelectedSendingFiles');
const _uuid = Uuid();

/// Manages files selected for sending.
/// Will stay alive even after a session has been completed to send the same files to another device.
final selectedSendingFilesProvider = ReduxProvider<SelectedSendingFilesNotifier, List<CrossFile>>((ref) {
  return SelectedSendingFilesNotifier();
});

class SelectedSendingFilesNotifier extends ReduxNotifier<List<CrossFile>> {
  @override
  List<CrossFile> init() => [];
}

class AddMessageAction extends ReduxAction<SelectedSendingFilesNotifier, List<CrossFile>> {
  final String message;
  final int? index;

  AddMessageAction({
    required this.message,
    this.index,
  });

  @override
  List<CrossFile> reduce() {
    final List<int> bytes = utf8.encode(message);
    final file = CrossFile(
      name: '${_uuid.v4()}.txt',
      fileType: FileType.text,
      size: bytes.length,
      thumbnail: null,
      asset: null,
      path: null,
      bytes: bytes,
    );

    return List.unmodifiable([
      ...state,
    ]..insert(index ?? state.length, file));
  }
}

class UpdateMessageAction extends ReduxAction<SelectedSendingFilesNotifier, List<CrossFile>> {
  final String message;
  final int index;

  UpdateMessageAction({
    required this.message,
    required this.index,
  });

  @override
  List<CrossFile> reduce() {
    dispatch(RemoveSelectedFileAction(index));
    dispatch(AddMessageAction(message: message, index: index));
    return state;
  }
}

class AddFilesAction<T> extends AsyncReduxAction<SelectedSendingFilesNotifier, List<CrossFile>> {
  final Iterable<T> files;
  final Future<CrossFile> Function(T) converter;

  AddFilesAction({
    required this.files,
    required this.converter,
  });

  @override
  Future<List<CrossFile>> reduce() async {
    final newFiles = <CrossFile>[];
    for (final file in files) {
      // we do it sequential because there are bugs
      // https://github.com/fluttercandies/flutter_photo_manager/issues/589
      newFiles.add(await converter(file));
    }
    return List.unmodifiable([
      ...state,
      ...newFiles,
    ]);
  }
}

/// Adds files inside the directory recursively.
class AddDirectoryAction extends AsyncReduxAction<SelectedSendingFilesNotifier, List<CrossFile>> {
  final String directoryPath;

  AddDirectoryAction(this.directoryPath);

  @override
  Future<List<CrossFile>> reduce() async {
    _logger.info('Reading files in $directoryPath');
    final newFiles = <CrossFile>[];
    final directoryName = p.basename(directoryPath);
    await for (final entity in Directory(directoryPath).list(recursive: true)) {
      if (entity is File) {
        final relative = '$directoryName/${p.relative(entity.path, from: directoryPath).replaceAll('\\', '/')}';
        _logger.info('Add file $relative');
        final file = CrossFile(
          name: relative,
          fileType: relative.guessFileType(),
          size: entity.lengthSync(),
          thumbnail: null,
          asset: null,
          path: entity.path,
          bytes: null,
        );
        newFiles.add(file);
      }
    }

    return List.unmodifiable([
      ...state,
      ...newFiles,
    ]);
  }
}

class RemoveSelectedFileAction extends ReduxAction<SelectedSendingFilesNotifier, List<CrossFile>> with GlobalActions {
  final int index;

  RemoveSelectedFileAction(this.index);

  @override
  List<CrossFile> reduce() {
    return List<CrossFile>.unmodifiable([...state]..removeAt(index));
  }

  @override
  void after() {
    if (state.isEmpty) {
      global.dispatch(ClearCacheAction());
    }
  }
}

class ClearSelectionAction extends ReduxAction<SelectedSendingFilesNotifier, List<CrossFile>> with GlobalActions {
  @override
  List<CrossFile> reduce() {
    return List.empty(growable: false);
  }

  @override
  void after() {
    global.dispatch(ClearCacheAction());
  }
}

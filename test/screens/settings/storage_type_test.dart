import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/models.dart';
import 'package:media_player/screens/settings/storage_type.dart';

Storage _storage(int id, String type) =>
    Storage(id: id, name: 's$id', type: type, enabled: true);

void main() {
  test('fromString recognizes known types and falls back to unknown', () {
    expect(StorageType.fromString('webdav'), StorageType.webdav);
    expect(StorageType.fromString('QUARK'), StorageType.quark);
    expect(StorageType.fromString('openlist'), StorageType.openlist);
    expect(StorageType.fromString('baidu'), StorageType.unknown);
    expect(StorageType.fromString(''), StorageType.unknown);
  });

  test('unknown is not selectable and has no handwritten form', () {
    expect(StorageType.selectable, isNot(contains(StorageType.unknown)));
    expect(StorageType.selectable, contains(StorageType.quark));
    expect(StorageType.quark.hasHandwrittenForm, isFalse);
    expect(StorageType.unknown.hasHandwrittenForm, isFalse);
    expect(StorageType.webdav.hasHandwrittenForm, isTrue);
  });

  test('group keeps unknown types out of the webdav group', () {
    final groups = StorageType.group([
      _storage(1, 'webdav'),
      _storage(2, 'quark'),
      _storage(3, 'baidu'),
    ]);
    expect(groups[StorageType.webdav]!.map((s) => s.id), [1]);
    expect(groups[StorageType.quark]!.map((s) => s.id), [2]);
    expect(groups[StorageType.unknown]!.map((s) => s.id), [3]);
  });

  test('typeDisplayName covers quark', () {
    expect(_storage(1, 'quark').typeDisplayName, '夸克网盘');
  });
}

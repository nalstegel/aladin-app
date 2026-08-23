import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_state.dart';

/// Vmesnik do shrambe. Ko preklopimo na Firebase, dodamo novo izvedbo
/// tega vmesnika in Repository ostane nespremenjen.
abstract class DataStore {
  Future<AppState?> load();
  Future<void> save(AppState state);
  Future<void> clear();
}

/// Shramba v pomnilniku — uporabna v testih.
class InMemoryStore implements DataStore {
  AppState? _state;

  @override
  Future<AppState?> load() async => _state;

  @override
  Future<void> save(AppState state) async => _state = state;

  @override
  Future<void> clear() async => _state = null;
}

/// Lokalni zapis stanja v JSON datoteko na napravi.
class LocalStore implements DataStore {
  static const _fileName = 'aladin_data.json';
  File? _file;

  Future<File> _resolve() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/$_fileName');
  }

  @override
  Future<AppState?> load() async {
    try {
      final f = await _resolve();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      return AppState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Poškodovana datoteka ne sme blokirati aplikacije — začnemo na novo.
      return null;
    }
  }

  @override
  Future<void> save(AppState state) async {
    final f = await _resolve();
    await f.writeAsString(jsonEncode(state.toJson()));
  }

  @override
  Future<void> clear() async {
    final f = await _resolve();
    if (await f.exists()) await f.delete();
  }
}

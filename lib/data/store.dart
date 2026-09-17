import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_user.dart';
import '../models/catalog.dart';
import '../models/customer.dart';
import '../models/order.dart';
import '../models/rug_item.dart';
import 'app_state.dart';

/// Vmesnik do shrambe. Zamenjava shrambe pomeni novo izvedbo tega vmesnika.
abstract class DataStore {
  Future<AppState?> load();
  Future<void> save(AppState state);
  Future<void> clear();

  /// Tok sprememb, ki so jih naredile DRUGE naprave.
  ///
  /// Shrambe brez sinhronizacije (lokalna datoteka, pomnilnik) vrnejo prazen
  /// tok — takrat aplikacija deluje kot prej, samo brez živih posodobitev.
  ///
  /// Emitirano stanje NE vsebuje `currentUserId` — kdo je prijavljen, je
  /// stvar posamezne naprave. Za to poskrbi [Repository].
  Stream<AppState> watch() => const Stream<AppState>.empty();
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

  @override
  Stream<AppState> watch() => const Stream<AppState>.empty();
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

  @override
  Stream<AppState> watch() => const Stream<AppState>.empty();
}

/// Skupna shramba v Firebase — vsi zaposleni na vseh telefonih delijo isto
/// stanje. `currentUserId` (kdo je prijavljen na TEM telefonu) namenoma NI
/// del sinhroniziranih podatkov — prijava na enem telefonu ne sme prepisati
/// prijave na vseh ostalih. Sejo hrani Firebase Auth sam, tudi brez
/// povezave, zato je tu ni treba posebej shranjevati.
class FirestoreStore implements DataStore {
  FirestoreStore({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  /// Zadnje shranjeno stanje — primerjava z njim pove, kateri zapisi so se
  /// dejansko spremenili, da ne pišemo cele baze ob vsaki spremembi enega
  /// kosa.
  AppState _lastSaved = const AppState();

  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection('customers');
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('items');
  CollectionReference<Map<String, dynamic>> get _rugTypes =>
      _db.collection('rugTypes');
  CollectionReference<Map<String, dynamic>> get _extraTemplates =>
      _db.collection('extraTemplates');
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  DocumentReference<Map<String, dynamic>> get _counters =>
      _db.collection('meta').doc('counters');

  @override
  Future<AppState?> load() async {
    final snaps = await Future.wait([
      _customers.get(),
      _orders.get(),
      _items.get(),
      _rugTypes.get(),
      _extraTemplates.get(),
      _users.get(),
    ]);
    final counters = await _counters.get();

    // Prazen projekt (prvi zagon) — naj Repository zapiše seed podatke.
    if (snaps[0].docs.isEmpty && snaps[1].docs.isEmpty && snaps[5].docs.isEmpty) {
      return null;
    }

    final state = AppState(
      customers: snaps[0].docs.map((d) => Customer.fromJson(d.data())).toList(),
      orders: snaps[1].docs.map((d) => WorkOrder.fromJson(d.data())).toList(),
      items: snaps[2].docs.map((d) => RugItem.fromJson(d.data())).toList(),
      rugTypes: snaps[3].docs.map((d) => RugType.fromJson(d.data())).toList(),
      extraTemplates:
          snaps[4].docs.map((d) => ExtraTemplate.fromJson(d.data())).toList(),
      users: snaps[5].docs.map((d) => AppUser.fromJson(d.data())).toList(),
      nextOrderSeqLjubljana:
          (counters.data()?['nextOrderSeqLjubljana'] as num?)?.toInt() ?? 1,
      nextOrderSeqMaribor:
          (counters.data()?['nextOrderSeqMaribor'] as num?)?.toInt() ?? 1,
    );
    _lastSaved = state;
    return state;
  }

  /// Posluša vse zbirke hkrati in ob vsaki spremembi sestavi novo stanje.
  ///
  /// Firestore ob naročilu takoj vrne trenutno vsebino, nato pa samo še
  /// spremembe. Lastne zapise vidimo takoj (Firestore jih v posnetek doda
  /// še preden jih strežnik potrdi), zato tok ne "povozi" sprememb, ki jih
  /// je pravkar naredil ta telefon.
  @override
  Stream<AppState> watch() {
    List<Customer>? customers;
    List<WorkOrder>? orders;
    List<RugItem>? items;
    List<RugType>? rugTypes;
    List<ExtraTemplate>? extraTemplates;
    List<AppUser>? users;
    int? nextOrderSeqLjubljana;
    int? nextOrderSeqMaribor;

    late final StreamController<AppState> controller;
    final subs = <StreamSubscription<dynamic>>[];

    void emit() {
      // Dokler nimamo vseh zbirk, bi bilo stanje nepopolno.
      if (customers == null ||
          orders == null ||
          items == null ||
          rugTypes == null ||
          extraTemplates == null ||
          users == null ||
          nextOrderSeqLjubljana == null ||
          nextOrderSeqMaribor == null) {
        return;
      }
      final state = AppState(
        customers: customers!,
        orders: orders!,
        items: items!,
        rugTypes: rugTypes!,
        extraTemplates: extraTemplates!,
        users: users!,
        nextOrderSeqLjubljana: nextOrderSeqLjubljana!,
        nextOrderSeqMaribor: nextOrderSeqMaribor!,
      );
      // Osnova za primerjavo pri naslednjem shranjevanju: objekti v tem
      // stanju so iste instance, ki jih bo Repository nosil naprej, zato
      // identical() v save() pravilno prepozna nespremenjene zapise.
      _lastSaved = state;
      controller.add(state);
    }

    void start() {
      subs.addAll([
        _customers.snapshots().listen((s) {
          customers = s.docs.map((d) => Customer.fromJson(d.data())).toList();
          emit();
        }, onError: controller.addError),
        _orders.snapshots().listen((s) {
          orders = s.docs.map((d) => WorkOrder.fromJson(d.data())).toList();
          emit();
        }, onError: controller.addError),
        _items.snapshots().listen((s) {
          items = s.docs.map((d) => RugItem.fromJson(d.data())).toList();
          emit();
        }, onError: controller.addError),
        _rugTypes.snapshots().listen((s) {
          rugTypes = s.docs.map((d) => RugType.fromJson(d.data())).toList();
          emit();
        }, onError: controller.addError),
        _extraTemplates.snapshots().listen((s) {
          extraTemplates =
              s.docs.map((d) => ExtraTemplate.fromJson(d.data())).toList();
          emit();
        }, onError: controller.addError),
        _users.snapshots().listen((s) {
          users = s.docs.map((d) => AppUser.fromJson(d.data())).toList();
          emit();
        }, onError: controller.addError),
        _counters.snapshots().listen((d) {
          nextOrderSeqLjubljana =
              (d.data()?['nextOrderSeqLjubljana'] as num?)?.toInt() ??
                  const AppState().nextOrderSeqLjubljana;
          nextOrderSeqMaribor =
              (d.data()?['nextOrderSeqMaribor'] as num?)?.toInt() ??
                  const AppState().nextOrderSeqMaribor;
          emit();
        }, onError: controller.addError),
      ]);
    }

    controller = StreamController<AppState>(
      onListen: start,
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> save(AppState state) async {
    final batch = _db.batch();
    var writes = 0;

    // Piše samo zapise, ki so se od zadnjega shranjevanja dejansko
    // spremenili (Repository ob vsaki spremembi zamenja samo prizadete
    // objekte, nedotaknjeni obdržijo isto referenco — identical() torej
    // zanesljivo loči spremenjeno od nespremenjenega).
    void diff<T>(
      CollectionReference<Map<String, dynamic>> col,
      List<T> oldList,
      List<T> newList,
      String Function(T) idOf,
      Map<String, dynamic> Function(T) toJson,
    ) {
      final oldById = {for (final e in oldList) idOf(e): e};
      for (final entity in newList) {
        final id = idOf(entity);
        if (identical(oldById[id], entity)) continue;
        batch.set(col.doc(id), toJson(entity));
        writes++;
      }
    }

    diff(_customers, _lastSaved.customers, state.customers, (c) => c.id,
        (c) => c.toJson());
    diff(_rugTypes, _lastSaved.rugTypes, state.rugTypes, (t) => t.id,
        (t) => t.toJson());
    diff(_extraTemplates, _lastSaved.extraTemplates, state.extraTemplates,
        (t) => t.id, (t) => t.toJson());
    diff(_users, _lastSaved.users, state.users, (u) => u.id, (u) => u.toJson());
    diff(_items, _lastSaved.items, state.items, (i) => i.id, (i) => i.toJson());

    // Naročila posebej: podpis pri vračilu naložimo v Storage, preden
    // zapišemo dokument, da Firestore dokument ostane majhen.
    final oldOrdersById = {for (final o in _lastSaved.orders) o.id: o};
    for (final order in state.orders) {
      if (identical(oldOrdersById[order.id], order)) continue;
      var payload = order.toJson();
      final proof = order.returnProof;
      if (proof != null &&
          (proof.signatureUrl == null || proof.signatureUrl!.isEmpty) &&
          proof.signatureBase64 != null &&
          proof.signatureBase64!.isNotEmpty) {
        final url = await _uploadSignature(order.id, proof.signatureBase64!);
        payload = order
            .copyWith(
              returnProof: proof.copyWith(
                signatureUrl: url,
                clearSignatureBase64: true,
              ),
            )
            .toJson();
      }
      batch.set(_orders.doc(order.id), payload);
      writes++;
    }

    if (state.nextOrderSeqLjubljana != _lastSaved.nextOrderSeqLjubljana ||
        state.nextOrderSeqMaribor != _lastSaved.nextOrderSeqMaribor) {
      batch.set(
        _counters,
        {
          'nextOrderSeqLjubljana': state.nextOrderSeqLjubljana,
          'nextOrderSeqMaribor': state.nextOrderSeqMaribor,
        },
        SetOptions(merge: true),
      );
      writes++;
    }

    if (writes > 0) await batch.commit();
    _lastSaved = state;
  }

  Future<String> _uploadSignature(String orderId, String base64Png) async {
    final bytes = base64Decode(base64Png);
    final ref = _storage.ref('signatures/$orderId.png');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
    return ref.getDownloadURL();
  }

  @override
  Future<void> clear() async {
    for (final col in [
      _customers,
      _orders,
      _items,
      _rugTypes,
      _extraTemplates,
      _users,
    ]) {
      final snap = await col.get();
      for (var i = 0; i < snap.docs.length; i += 400) {
        final chunk = _db.batch();
        for (final d in snap.docs.skip(i).take(400)) {
          chunk.delete(d.reference);
        }
        await chunk.commit();
      }
    }
    await _counters.delete();
    _lastSaved = const AppState();
  }
}

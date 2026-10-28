/// Digitalno dokazilo, da so bile preproge dejansko vrnjene stranki.
class ReturnProof {
  final DateTime returnedAt;
  final String userId;
  final String userName;

  /// ID-ji vseh kosov, ki so bili ob predaji poskenirani.
  final List<String> scannedItemIds;

  /// Podpis stranke kot PNG, zapisan v base64. Zapisan takoj ob podpisu;
  /// FirestoreStore ga ob shranjevanju naloži v Firebase Storage in tu
  /// zapiše [signatureUrl], nato base64 iz Firestore dokumenta izpusti.
  final String? signatureBase64;

  /// URL podpisa v Firebase Storage, potem ko ga FirestoreStore naloži.
  final String? signatureUrl;

  /// Ime osebe, ki je prevzela preproge.
  final String receivedByName;

  /// Če podpisa ni bilo — razlog in kdo je odobril obvod.
  final String? overrideReason;
  final String? overrideByName;

  const ReturnProof({
    required this.returnedAt,
    required this.userId,
    required this.userName,
    required this.scannedItemIds,
    this.signatureBase64,
    this.signatureUrl,
    this.receivedByName = '',
    this.overrideReason,
    this.overrideByName,
  });

  bool get hasSignature =>
      (signatureUrl != null && signatureUrl!.isNotEmpty) ||
      (signatureBase64 != null && signatureBase64!.isNotEmpty);
  bool get isOverride => overrideReason != null && overrideReason!.isNotEmpty;

  ReturnProof copyWith({String? signatureUrl, bool clearSignatureBase64 = false}) =>
      ReturnProof(
        returnedAt: returnedAt,
        userId: userId,
        userName: userName,
        scannedItemIds: scannedItemIds,
        signatureBase64: clearSignatureBase64 ? null : signatureBase64,
        signatureUrl: signatureUrl ?? this.signatureUrl,
        receivedByName: receivedByName,
        overrideReason: overrideReason,
        overrideByName: overrideByName,
      );

  Map<String, dynamic> toJson() => {
        'returnedAt': returnedAt.toIso8601String(),
        'userId': userId,
        'userName': userName,
        'scannedItemIds': scannedItemIds,
        'signatureBase64': signatureBase64,
        'signatureUrl': signatureUrl,
        'receivedByName': receivedByName,
        'overrideReason': overrideReason,
        'overrideByName': overrideByName,
      };

  factory ReturnProof.fromJson(Map<String, dynamic> j) => ReturnProof(
        returnedAt: DateTime.parse(j['returnedAt'] as String),
        userId: j['userId'] as String? ?? '',
        userName: j['userName'] as String? ?? '',
        scannedItemIds:
            (j['scannedItemIds'] as List? ?? []).map((e) => '$e').toList(),
        signatureBase64: j['signatureBase64'] as String?,
        signatureUrl: j['signatureUrl'] as String?,
        receivedByName: j['receivedByName'] as String? ?? '',
        overrideReason: j['overrideReason'] as String?,
        overrideByName: j['overrideByName'] as String?,
      );
}

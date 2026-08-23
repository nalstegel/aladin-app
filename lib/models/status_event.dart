import 'enums.dart';

/// Zapis v zgodovini preproge — kdo je kdaj kaj naredil.
class StatusEvent {
  final RugStatus status;
  final DateTime at;
  final String userId;
  final String userName;
  final String note;

  const StatusEvent({
    required this.status,
    required this.at,
    required this.userId,
    required this.userName,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'at': at.toIso8601String(),
        'userId': userId,
        'userName': userName,
        'note': note,
      };

  factory StatusEvent.fromJson(Map<String, dynamic> j) => StatusEvent(
        status: RugStatus.values.byName(j['status'] as String),
        at: DateTime.parse(j['at'] as String),
        userId: j['userId'] as String? ?? '',
        userName: j['userName'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

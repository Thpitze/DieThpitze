// lib/core/records/record_header.dart
class RecordHeader {
  final String id;
  final String updatedAtUtc;
  final String type;
  final List<String> tags;
  final String title;

  RecordHeader({
    required this.id,
    required this.updatedAtUtc,
    required this.type,
    required this.tags,
    required this.title,
  });
}

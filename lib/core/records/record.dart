// lib/core/records/record.dart
class Record {
  final String id; // UUID
  final String createdAtUtc; // ISO 8601 UTC
  final String updatedAtUtc; // ISO 8601 UTC
  final String type; // e.g. "note"
  final List<String> tags;
  final String bodyMarkdown;

  Record({
    required this.id,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.type,
    required this.tags,
    required this.bodyMarkdown,
  });

  Record copyWith({
    String? updatedAtUtc,
    String? type,
    List<String>? tags,
    String? bodyMarkdown,
  }) {
    return Record(
      id: id,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      bodyMarkdown: bodyMarkdown ?? this.bodyMarkdown,
    );
  }
}

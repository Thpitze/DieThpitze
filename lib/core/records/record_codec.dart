// lib/core/records/record_codec.dart
import 'package:yaml/yaml.dart';

import 'package:thpitze_main/core/vault/vault_errors.dart';
import 'package:thpitze_main/core/records/record.dart';

class RecordCodec {
  static const String _sep = '---';

  String encode(Record r) {
    final tagsYaml = r.tags.map((t) => '  - ${_escapeYamlScalar(t)}').join('\n');

    final frontmatter = StringBuffer()
      ..writeln(_sep)
      ..writeln('id: ${r.id}')
      ..writeln('createdAtUtc: ${r.createdAtUtc}')
      ..writeln('updatedAtUtc: ${r.updatedAtUtc}')
      ..writeln('type: ${_escapeYamlScalar(r.type)}');

    if (r.tags.isNotEmpty) {
      frontmatter.writeln('tags:');
      frontmatter.writeln(tagsYaml);
    } else {
      frontmatter.writeln('tags: []');
    }

    frontmatter
      ..writeln(_sep)
      ..writeln();

    return frontmatter.toString() + r.bodyMarkdown;
  }

  Record decode(String markdownFileContent) {
    final parts = _splitFrontmatter(markdownFileContent);

    final yamlText = parts.yamlText;
    final body = parts.body;

    final parsed = loadYaml(yamlText);
    if (parsed is! YamlMap) {
      throw VaultInvalidException('Record frontmatter is not a YAML map.');
    }

    String reqString(String key) {
      final v = parsed[key];
      if (v is! String || v.trim().isEmpty) {
        throw VaultInvalidException('Record frontmatter missing/invalid "$key".');
      }
      return v;
    }

    final id = reqString('id');
    final createdAtUtc = reqString('createdAtUtc');
    final updatedAtUtc = reqString('updatedAtUtc');
    final type = reqString('type');

    final tagsNode = parsed['tags'];
    final tags = <String>[];
    if (tagsNode is YamlList) {
      for (final e in tagsNode) {
        if (e is String && e.trim().isNotEmpty) tags.add(e);
      }
    } else if (tagsNode == null) {
      // allow missing tags, treat as empty
    } else if (tagsNode is String && tagsNode.trim().isEmpty) {
      // ignore
    } else {
      // allow tags: [] which becomes YamlList; other types are invalid
      throw VaultInvalidException('Record frontmatter "tags" must be a YAML list.');
    }

    return Record(
      id: id,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc,
      type: type,
      tags: tags,
      bodyMarkdown: body,
    );
  }

  ({String yamlText, String body}) _splitFrontmatter(String content) {
    final normalized = content.replaceAll('\r\n', '\n');

    if (!normalized.startsWith('$_sep\n')) {
      throw VaultInvalidException('Record file must start with YAML frontmatter (---).');
    }

    final end = normalized.indexOf('\n$_sep\n', _sep.length + 1);
    if (end < 0) {
      throw VaultInvalidException('Record YAML frontmatter is not terminated with ---.');
    }

    final yamlStart = _sep.length + 1; // after first '---\n'
    final yamlText = normalized.substring(yamlStart, end);

    final bodyStart = end + ('\n$_sep\n').length;
    final body = normalized.substring(bodyStart);

    return (yamlText: yamlText, body: body);
  }

  String _escapeYamlScalar(String s) {
    // Minimal: quote if it contains colon or leading/trailing whitespace.
    final needsQuotes = s.contains(':') || s.trim() != s || s.contains('#');
    if (!needsQuotes) return s;
    final escaped = s.replaceAll('"', r'\"');
    return '"$escaped"';
  }
}

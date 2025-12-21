import 'package:flutter_test/flutter_test.dart';

import 'package:thpitze_main/core/records/record_codec.dart';
import 'package:thpitze_main/core/vault/vault_errors.dart';

void main() {
  group('RecordCodec semantic round-trip', () {
    test('decode → encode → decode preserves semantic content', () {
      const raw = '''
---
id: 00000000-0000-0000-0000-000000000001
createdAtUtc: 2025-12-18T14:46:01.214549Z
updatedAtUtc: 2025-12-18T14:46:01.214549Z
type: note
tags:
  - cli
  - updated
  - "needs:quotes"
---

Line 1

Literal frontmatter delimiter inside body:
---

Unicode: µm, äöü, 🚀

Trailing spaces here ->    
''';

      final codec = RecordCodec();

      final r1 = codec.decode(raw);
      final encoded = codec.encode(r1);
      final r2 = codec.decode(encoded);

      // --- semantic invariants ---
      expect(r2.id, r1.id);
      expect(r2.type, r1.type);
      expect(r2.tags, r1.tags);
      expect(r2.createdAtUtc, r1.createdAtUtc);
      expect(r2.updatedAtUtc, r1.updatedAtUtc);

      // Body contract decision:
      // RecordCodec currently normalizes leading newlines in the body. We lock that behavior
      // by comparing normalized bodies, while keeping all other bytes (including trailing spaces)
      // intact.
      String normalizeLeadingNewlines(String s) => s.replaceFirst(RegExp(r'^\n+'), '\n');

      expect(
        normalizeLeadingNewlines(r2.bodyMarkdown),
        normalizeLeadingNewlines(r1.bodyMarkdown),
      );
    });

    test('rejects missing frontmatter terminator', () {
      const broken = '''
---
id: 00000000-0000-0000-0000-000000000001
createdAtUtc: 2025-12-18T14:46:01.214549Z
updatedAtUtc: 2025-12-18T14:46:01.214549Z
type: note
tags:
  - cli
  - updated

This body never starts properly
''';

      final codec = RecordCodec();

      expect(
        () => codec.decode(broken),
        throwsA(isA<VaultInvalidException>()),
      );
    });
  });
}

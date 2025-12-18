Thpitze — Vault Contract v0
Date: 2025-12-17
Status: Draft / v0
Scope: Defines the on-disk data model (“vault”) independent of application implementation.
________________________________________
1. Purpose
The vault is the sole source of truth for all user-owned data in Thpitze.
The vault must:
•	remain usable without Thpitze
•	remain readable with generic tools
•	survive application evolution
•	support external sync and backup
The vault is explicitly not an application cache, database, or UI artifact.
________________________________________
2. Core principles (non-negotiable)
1.	File-based
All primary data is stored as normal files in a directory structure.
2.	Open formats
Data must be readable without proprietary software.
3.	Deterministic
Same input → same serialized output (no random ordering, no hidden state).
4.	Tool-agnostic
The vault does not depend on Flutter, Dart, or Thpitze internals.
5.	Future-tolerant
Old vaults must remain readable by newer versions of the application.


---
name: local-toolchain-baseline
description: Verified local toolchain versions (Python 3.14, Node 26, uv) and the passlib/bcrypt breakage that invalidates the standard FastAPI auth tutorial
metadata:
  type: project
---

Dev machine toolchain, empirically verified 2026-08-27 by installing and running the stack:

- Python **3.14.6** (Homebrew, `/opt/homebrew/bin/python3`), pip 26.1.2, sqlite3 3.53.4
- Node **v26.7.0**, npm 11.19.0
- `uv` 0.12.1 available; **`poetry`, `pnpm`, `yarn` are NOT installed**
- No PEP 668 `EXTERNALLY-MANAGED` marker, but use venv/uv anyway

Two findings that break the "obvious" recommendation for Python auth work:

1. **`passlib[bcrypt]` is broken here.** `CryptContext(schemes=["bcrypt"]).hash()` raises
   `ValueError: password cannot be longer than 72 bytes` against bcrypt 5.0.0. passlib 1.7.4
   (unmaintained since 2020) probes with a >72-byte self-test hash that bcrypt >=4.1 now rejects
   instead of truncating. Verified fix: use **`pwdlib`** (works out of the box, argon2id default)
   or call `bcrypt` directly. Pinning `bcrypt==4.0.1` also rescues passlib but keeps a dead dep.
2. **Python 3.13+ removed the stdlib `crypt` module** — confirmed `ModuleNotFoundError` here.
   Any recommendation that transitively depends on `crypt` is dead on this machine.

Also: the Vite `react-ts` template now scaffolds React 19 / Vite 8 / TypeScript 6 and uses
**oxlint, not ESLint** — do not expect an `eslint.config.js`.

**Why:** These are bleeding-edge runtimes. The most-copied FastAPI security tutorial pattern
(`passlib[bcrypt]` + `python-jose`) fails on contact, so recommending it wastes an
implementation cycle on a confusing runtime error.

**How to apply:** When researching or planning Python/Node work for this environment, recommend
`pwdlib` over `passlib` and `pyjwt` over `python-jose` (jose is also effectively unmaintained).
Re-verify versions if this memory is more than a few months old — toolchains here move fast.

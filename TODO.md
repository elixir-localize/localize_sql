# TODO

Keeping `localize_sql` in step with the ICU a PostgreSQL server links, the
PostgreSQL major, Localize's bundled CLDR and OTP's Unicode. The reasoning and
the annual October–November review window are in
[plans/collation-inventory.md](plans/collation-inventory.md).

## Open

* [ ] **Release the corrected `@cldr_unicode_versions`** — the map in `lib/localize/ecto/audit.ex` was wrong for `48` and `49` (now `"17.0"` and `"18.0"`), and the docs are fixed to match. Until the package is released, an installed `mix localize.ecto.audit` still prints `Unicode 16.0` and raises a spurious drift warning against an ICU 77 server.

* [ ] **Make the collation inventory a runtime fact** — query `pg_collation` once per repo, cache it, and use it as the `:available` set for `Localize.Ecto.Collation.collation_for/2`, falling back to the bundled list only where no repo exists. The one real API change: `collation_for/2` is pure today and needs a repo passed or configured.

* [ ] **Teach `Localize.Ecto.Audit` about inventory drift** — report collation locales the server offers that the bundled list lacks (a missed opportunity) and any the list has that the server lacks (a latent runtime error).

* [ ] **Surface `collversion` mismatches prominently** — the only failure here with data-integrity consequences; PostgreSQL records it, the audit should make it loud and name `REINDEX`.

## Blocked

* [ ] **Derive the Unicode version from Localize instead of a hand-maintained map** — Blocked on Localize exposing `unicode_version/0`, readable from the `[UCA version = ...]` line in `FractionalUCA.txt` at collation-table build time. Deletes `@cldr_unicode_versions` entirely.

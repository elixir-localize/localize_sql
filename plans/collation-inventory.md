# Collation inventory and version drift

**Status:** planning, 2026-09-21

`localize_sql` has to stay in step with four independently versioned moving
parts: the ICU a PostgreSQL server happens to link, the PostgreSQL major, the
CLDR version bundled in Localize, and Elixir/OTP's own Unicode. This document
records the reasoning; the work is tracked in [TODO.md](../TODO.md).

## The bundled snapshot is a floor, never a ceiling

The bundled `priv/localize_sql/pg_icu_collations.txt` is a build-time snapshot
of a runtime fact, and the two drift directions are not symmetric. A snapshot
**older** than the server degrades silently and harmlessly — a locale resolves
to a broader collation that still exists. A snapshot **newer** than the server
is a hard `collation "xx-x-icu" for encoding "UTF8" does not exist` error at
query time.

The inventory is determined by the **ICU version the server links, not the
PostgreSQL major** — a PG 17 built against ICU 77 has the newer locales and a
PG 18 against ICU 76 does not — so no static snapshot can ever be keyed
correctly to a PostgreSQL version.

Current policy, recorded here so the reasoning is not lost the next time the
file looks stale: the shipped list stays at the oldest supported ICU inventory,
so it can only ever degrade gracefully. Regenerating it against a newer server
would break users on older ICU builds.

## The version-proof answer: make the inventory a runtime fact

Query `pg_collation` once per repo, cache it, and use that as the `:available`
set for `Localize.Ecto.Collation.collation_for/2`, falling back to the bundled
list only where no repo is available (SQLite, compile-time resolution). This
removes both drift directions permanently. It is the one real API change in
this area — `collation_for/2` is currently pure and would need a repo passed or
configured.

## `collversion` mismatches have data-integrity consequences

Of everything here this is the only failure with data-integrity consequences —
an ICU tailoring change silently invalidates existing index ordering, and the
fix is `REINDEX`. PostgreSQL already records the mismatch; the audit should
make it loud.

## Localize records no Unicode version

There is no `unicode_version/0` accessor and nothing in the supplemental data,
which is why this library carries a hand-maintained `@cldr_unicode_versions`
lookup table that has now been wrong twice. Deriving it from the shipped CLDR
data — the `[UCA version = ...]` line in `FractionalUCA.txt` is right there at
collation-table build time — would let the audit read a fact instead of a
guess, and would delete the map entirely.

## Cadence

Unicode ships each September, ICU follows, CLDR releases in spring and autumn,
and PostgreSQL majors land September–October. Everything moves at once, so
October–November is the natural annual window to regenerate the snapshot,
re-run the audit against a current server, and re-verify the version claims in
the docs. Unicode 18 is expected September 2026 and CLDR 49 in October 2026,
and CLDR main is already building against UCA/UCD 18.0.0.

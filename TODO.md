# TODO

Keeping `localize_sql` in step with four independently-versioned moving parts: the ICU a PostgreSQL server happens to link, the PostgreSQL major, the CLDR version bundled in Localize, and Elixir/OTP's own Unicode. Grouped by whether the work is blocked on Localize.

## Pending release

* **The corrected `@cldr_unicode_versions` needs a package release, not just a docs publish.** The map in [lib/localize/ecto/audit.ex](lib/localize/ecto/audit.ex) was wrong for its two most recent entries — `48 => "16.0"` and `49 => "17.0"` where the truth is `48 => "17.0"` and `49 => "18.0"` — and the docs describing the audit's output were wrong to match. Both are fixed here, but until the package itself is released, an installed `mix localize.ecto.audit` will still print `Unicode 16.0` for the application and raise a spurious drift warning against an ICU 77 server, which the republished docs now say should not appear.

## Collation inventory

The bundled `priv/localize_sql/pg_icu_collations.txt` is a build-time snapshot of a runtime fact, and the two drift directions are not symmetric. A snapshot **older** than the server degrades silently and harmlessly — a locale resolves to a broader collation that still exists. A snapshot **newer** than the server is a hard `collation "xx-x-icu" for encoding "UTF8" does not exist` error at query time. The inventory is determined by the **ICU version the server links, not the PostgreSQL major** — a PG 17 built against ICU 77 has the newer locales and a PG 18 against ICU 76 does not — so no static snapshot can ever be keyed correctly to a PostgreSQL version.

* **Treat the bundled snapshot as a floor, never a ceiling.** This is the current policy: the shipped list stays at the oldest supported ICU inventory, so it can only ever degrade gracefully. Regenerating it against a newer server would break users on older ICU builds. Recorded here so the reasoning is not lost the next time the file looks stale.

* **Make the inventory a runtime fact.** Query `pg_collation` once per repo, cache it, and use that as the `:available` set for `Localize.Ecto.Collation.collation_for/2`, falling back to the bundled list only where no repo is available (SQLite, compile-time resolution). This removes both drift directions permanently and is the only version-proof answer. It is the one real API change in this list — `collation_for/2` is currently pure and would need a repo passed or configured.

* **Teach `Localize.Ecto.Audit` about inventory drift**, not just version drift: report collation locales the server offers that the bundled list lacks (a missed-opportunity warning) and any the list has that the server lacks (a latent runtime error).

* **Surface `collversion` mismatches prominently.** Of everything in this file this is the only failure with data-integrity consequences — an ICU tailoring change silently invalidates existing index ordering, and the fix is `REINDEX`. PostgreSQL already records the mismatch; the audit should make it loud.

## Blocked on Localize

* **`Localize` records no Unicode version anywhere.** There is no `unicode_version/0` accessor and nothing in the supplemental data, which is why this library carries a hand-maintained `@cldr_unicode_versions` lookup table that has now been wrong twice. Deriving it from the shipped CLDR data — the `[UCA version = ...]` line in `FractionalUCA.txt` is right there at collation-table build time — would let the audit read a fact instead of a guess, and would delete the map entirely.

## Cadence

Unicode ships each September, ICU follows, CLDR releases in spring and autumn, and PostgreSQL majors land September–October. Everything moves at once, so October–November is the natural annual window to regenerate the snapshot, re-run the audit against a current server, and re-verify the version claims in the docs. Unicode 18 is expected September 2026 and CLDR 49 in October 2026, and CLDR main is already building against UCA/UCD 18.0.0.

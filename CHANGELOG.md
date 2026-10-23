# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-24

### Changed

* Requires `localize ~> 1.4`, which bundles CLDR 49 (Unicode 18.0).

* `Localize.Territory.Ecto.Type` casts a CLDR territory alias to its code, as `Localize.validate_territory/1` does: `"840"` casts to `:US` and `"UK"` to `:GB`.

### Fixed

* `mix localize.ecto.audit` no longer fails on a Unicode version gap between the server's ICU and the application's CLDR; it prints the warning and succeeds, as documented.

* The time zone audit no longer reports CLDR's `Etc/Unknown` placeholder as unknown to the server, which made the audit fail on every server.

## [1.0.1] - 2026-08-11

### Fixed

* The CLDR-to-Unicode version table behind `Localize.Ecto.Audit.unicode_versions/1` recorded CLDR 48 as Unicode 16.0 and CLDR 49 as 17.0; the correct values are 17.0 and 18.0. `mix localize.ecto.audit` no longer reports spurious drift against a PostgreSQL 18 server linked against ICU 77, which is also Unicode 17.

### Changed

* The collation guide now recommends the builtin providers over `C.UTF-8` as a version ladder — `PG_UNICODE_FAST` on PostgreSQL 18+, `PG_C_UTF8` on 17, `C` earlier — and documents their equivalence to Elixir's own string ordering. `PG_UNICODE_FAST` keeps the prefix-`LIKE` index optimization that ICU collations forgo.

## [1.0.0] - 2026-07-31

Renamed from `localize_ecto` to **`localize_sql`** — the package is about SQL databases (collations, serialization, migrations), not Ecto in general, which can be used without a database. The `Localize.Ecto.*` module namespace and the `mix localize.ecto.audit` task are unchanged; the app, config key (`:localize_sql`), env var (`LOCALIZE_SQL_SQLITE_ICU`) and `priv/localize_sql/` path are renamed.

`localize_sql` grows from locale-aware collation into the SQL home for every Localize type — serializing the full set of Localize and Elixir data types and generating the tagged-decimal aggregate machinery `ex_money_sql` builds on.

### Added

* `Localize.Ecto.TaggedDecimal` and its `DDL` generate a PostgreSQL composite type with tag-guarded `sum`/`avg`/`min`/`max` aggregates and `+`/`-` operators for any tag-plus-decimal value; a mismatched tag (euros plus yen) raises in the database. `ex_money_sql` now builds `money_with_currency` on this rather than its own SQL.

* Unit serialization, folded in from `localize_units_sql`: `Localize.Unit.Ecto.{Composite,Map}.Type` and the `Localize.UnitWithUsage` variants, `Localize.Unit.DDL` (now `sum`/`min`/`max`/`avg` for `cldr_unit` and `cldr_unit_with_usage`), and `mix localize.unit.gen.migration`.

* Ecto types for the remaining data types: `Localize.Currency.Ecto.Type`, `Localize.LanguageTag.Ecto.Type`, `Localize.Territory.Ecto.Type` and `Localize.Script.Ecto.Type` (text); `Localize.Ecto.Type.IntegerRange` and `.DateRange` (`int8range`/`daterange`); `Localize.Duration.Ecto.Type` and `Localize.Ecto.Type.Duration` (`interval`).

* `Localize.Ecto.Range` provides query macros for PostgreSQL range columns — containment, overlap, adjacency, the bound accessors and the range aggregates — and `Localize.Ecto.Range.Migration` creates a time range type, the `btree_gist` extension and the `no_overlap/3` exclusion constraint that forbids overlapping bookings.

* `Localize.Ecto.Migration.Generator` renders and writes migrations for the SQL-generating mix tasks.

### Fixed

* `Localize.UnitWithUsage.Ecto.Composite.Type.cast/1` now accepts a string-keyed map with no `"usage"` key, casting it as a unit without a usage. Only the atom-keyed form tolerated the key's absence, so an HTML form — which submits string keys — could not cast a unit unless it also submitted a usage.

### Changed

* Requires `localize ~> 1.0`. `postgrex` is an optional dependency; the range, duration and tagged-decimal composite types compile only when it is present, so a SQLite-only or collation-only consumer carries nothing extra.

* The `localize_units_sql` package is superseded — its unit serialization is folded in here, and its `sum`-only aggregates are replaced by `sum`, `min`, `max` and `avg` for both `cldr_unit` and `cldr_unit_with_usage`.

## [1.0.0-rc.0] - 2026-07-28

The 1.0 release candidate. `localize_ecto` now supports SQLite as well as PostgreSQL, with the same locale resolving to the same collation on both.

### Added

* SQLite support via `localize_icu`, a bundled SQLite loadable extension that registers ICU collations under the same names PostgreSQL uses. The same locale sorts identically on both databases.

* `Localize.Ecto.SQLite3` provides `collate/1,2`, `lower/1,2`, `upper/1,2` and `initcap/1,2` for SQLite. BCP 47 tailorings such as `-u-co-phonebk` need no migration; collations are registered on demand.

* `Localize.Ecto.SQLite3.Extension` locates the compiled extension for the `:load_extensions` option of Exqlite and `Ecto.Adapters.SQLite3`.

* `Localize.Ecto.Postgres` names the PostgreSQL macros explicitly, alongside the new SQLite module.

### Notes

* SQLite compares canonically equivalent strings (the NFC and NFD forms of `café`) as equal where PostgreSQL, using deterministic collations, compares them as unequal. Ordering agrees on both; normalizing on write removes the difference.

### Changed

* The SQLite extension is an opt-in build (`config :localize_ecto, :sqlite_icu, true`, or `LOCALIZE_ECTO_SQLITE_ICU=true`). Without it the package stays pure Elixir and PostgreSQL users are unaffected.

* Query macros emit Ecto's `identifier/1` rather than the deprecated `literal/1`. The generated SQL is unchanged.

## [0.3.0] - 2026-07-23

### Added

* Collation resolution carries all collation-affecting BCP 47 `-u-` keywords (`kn`, `ks`, `kc`, `kf`, `ka`, `kb`, `kr`, `kv`) into the collation name, so `collate(f.name, "en-u-kn-true")` finds a natural-sort collation created in a migration.

* `create_collation/2` accepts tailoring options (`:strength`, `:numeric`, `:case_level`, `:case_first`, `:alternate`, `:backwards`) using the `Localize.Collation.Options` vocabulary. Primary and secondary strengths default to a nondeterministic collation, enabling case/accent-insensitive equality and unique indexes.

* `mix localize.ecto.audit` and `Localize.Ecto.Audit` report collation version drift with per-index remediation SQL, database default collation drift, server-versus-application Unicode/ICU/CLDR versions, and time zone inventory differences.

* `Localize.Ecto.Type.TimeZone` is an Ecto type for IANA time zone identifiers, canonicalizing aliases and BCP 47 short zone ids against the CLDR inventory; `at_time_zone/2` applies a validated `AT TIME ZONE`.

* `Localize.Ecto.TextSearch.config_for/2` resolves a locale to the best PostgreSQL text search configuration, and `ts_match/2,3` builds a locale-aware `to_tsvector … @@ websearch_to_tsquery` match.

* `lower/1,2`, `upper/1,2` and `initcap/1,2` apply locale-aware case mapping via the locale's collation ("INDIGO" lowercases to "ındıgo" under `"tr"`).

### Changed

* Requires Localize `~> 1.0-rc.1` for the CLDR time zone inventory.

## [0.2.0] - 2026-07-23

### Changes

* Requires Localize `~> 1.0-rc`

## [0.1.0] - 2026-07-17

Initial release.

### Highlights

* `Localize.Ecto.collate/1,2` query macros applying PostgreSQL ICU `COLLATE` clauses to query expressions and comparisons, resolved from a locale or the current `Localize` locale.

* Locale-to-collation resolution via CLDR language matching, including BCP 47 `-u-co-` collation types and direct collation names.

* `Localize.Ecto.Migration.create_collation/2` and `drop_collation/2` for creating ICU collations reversibly in migrations, and `collated/2` for building collated indexes with `Ecto.Migration.index/3`.

See the [README](https://hexdocs.pm/localize_ecto/readme.html) for full documentation.

# Localize Ecto

Locale-aware ICU collation for [Ecto](https://hexdocs.pm/ecto) queries on PostgreSQL and SQLite. `localize_ecto` resolves a [Localize](https://hexdocs.pm/localize) language tag to the best matching ICU collation and applies it with a `COLLATE` clause, so query results sort and compare according to the conventions of the user's locale.

```elixir
import Ecto.Query
import Localize.Ecto

# Order by the current locale (Localize.get_locale/0)
from p in Product, order_by: collate(p.name)

# Order by an explicit locale
from p in Product, order_by: collate(p.name, "sv")

# Collate a comparison
from p in Product, where: collate(p.name < "münchen", "de")

# Use a collation created in a migration, by name
from p in Product, order_by: collate(p.name, collation: "german_phonebook")
```

The examples above are PostgreSQL. `Localize.Ecto` exposes the PostgreSQL macros directly; for SQLite, import [Localize.Ecto.SQLite3](https://hexdocs.pm/localize_ecto/Localize.Ecto.SQLite3.html) instead — see [SQLite](#sqlite) below.

Locale resolution uses the [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching) algorithm, so any valid locale finds its best available collation — `"zh-TW"` resolves to `zh-Hant-x-icu`, `"de-DE"` to `de-x-icu`, and an unknown locale falls back gracefully. Locales that carry a BCP 47 collation type, such as `de-u-co-phonebk` (German phonebook order), resolve to collations you create once in a migration with [Localize.Ecto.Migration.create_collation/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#create_collation/2).

## Beyond ordering

Collation tailoring, locale-aware search and case mapping, time zones, and operational auditing are covered by the same locale-first API:

```elixir
# Natural sort: "file2" before "file10" (create the collation once in a migration)
create_collation("en", numeric: true)
from f in Upload, order_by: collate(f.name, "en-u-kn-true")

# Case-insensitive uniqueness without citext: a nondeterministic collation
# at secondary strength, backing a unique index
create_collation("und", strength: :secondary)
create index("users", [collated(:email, "und-u-ks-level2")], unique: true)

# Locale-aware full-text search: German stemming matches "Häuser" from "Haus"
from a in Article, where: ts_match(a.body, "Haus", "de")

# Locale-aware case mapping: Turkish lower("INDIGO") is "ındıgo"
from p in Product, select: lower(p.name, "tr")

# Time zones validated against the CLDR inventory
field :time_zone, Localize.Ecto.Type.TimeZone
from e in Event, select: at_time_zone(e.starts_at, "Australia/Sydney")
```

The [audit task](https://hexdocs.pm/localize_ecto/Mix.Tasks.Localize.Ecto.Audit.html) reports collation version drift after PostgreSQL/ICU upgrades — with the `REINDEX` and `ALTER COLLATION … REFRESH VERSION` remediation for every dependent index — and compares the server's Unicode, ICU and time zone inventories against the application's:

```console
$ mix localize.ecto.audit
Audit for MyApp.Repo
  Collation versions: no drift
  Database default collation: no drift
  Server: PostgreSQL 17.4, Unicode 15.1, ICU Unicode 16.0
  Application: CLDR 48.0.0, Unicode 16.0
  Time zones: all application zones known to the server (14 server-only zones)
```

## Installation

Add `localize_ecto` to your dependencies:

```elixir
def deps do
  [
    {:localize_ecto, "~> 0.3.0"}
  ]
end
```

## SQLite

SQLite has no ICU collations of its own, so `localize_ecto` ships one: `localize_icu`, a SQLite loadable extension that registers ICU collations under the same names PostgreSQL uses. The same locale resolves to the same collation name and produces the same ordering on either database, so a query ported between them sorts identically — the test suite asserts this for a range of languages and tailorings.

Install ICU (`brew install icu4c`, or `apt-get install libicu-dev`), enable the build in `config/config.exs`, and load the extension on every connection:

```elixir
# config/config.exs — read at compile time, so not runtime.exs
config :localize_ecto, :sqlite_icu, true

# config/runtime.exs
config :my_app, MyApp.Repo,
  load_extensions: Localize.Ecto.SQLite3.Extension.load_extensions()
```

Then import [Localize.Ecto.SQLite3](https://hexdocs.pm/localize_ecto/Localize.Ecto.SQLite3.html) in place of `Localize.Ecto`:

```elixir
import Ecto.Query
import Localize.Ecto.SQLite3

from p in Product, order_by: collate(p.name, "sv")

# No migration needed: SQLite collations are registered on demand
from p in Product, order_by: collate(p.name, "de-u-co-phonebk")
```

Collations are built the first time a query names one, so unlike PostgreSQL the BCP 47 tailorings — `-u-co-phonebk`, `-u-kn-true`, `-u-ks-level1` — need no `CREATE COLLATION` migration. The build is opt-in: without it `localize_ecto` stays a pure-Elixir package needing no C toolchain or ICU, and PostgreSQL users are unaffected.

One consequence to weigh before indexing with an ICU collation: an index that names a collation makes the database unreadable by any connection that has not loaded the extension, including the `sqlite3` CLI. The [Collations in SQLite](https://hexdocs.pm/localize_ecto/collations_in_sqlite.html) guide covers this, the case mapping differences, and what does not port from PostgreSQL.

## Deterministic collations and Unicode normalization

The collations this library resolves to are deterministic, which is PostgreSQL's default. A deterministic collation never treats two strings as equal unless they are byte-for-byte identical: comparison first uses the linguistic collation order, then breaks ties bytewise. This has a practical consequence for Unicode text that is not normalized. Canonically equivalent strings in different normalization forms — for example `é` as the single code point U+00E9 versus `e` followed by combining U+0301 — will sort adjacently but will never compare equal, so equality tests, `DISTINCT`, `GROUP BY`, joins on text keys, and unique indexes all see them as different values.

To get expected results, normalize text (NFC is the usual choice) before writing it to the database. In Elixir use [String.normalize/2](https://hexdocs.pm/elixir/String.html#normalize/2); in PostgreSQL the [normalize](https://www.postgresql.org/docs/current/functions-string.html) function and `IS NFC NORMALIZED` predicate are available for checking or repairing existing data. Alternatively, PostgreSQL supports nondeterministic collations that do compare canonically equivalent strings as equal — [Localize.Ecto.Migration.create_collation/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#create_collation/2) can create one with `deterministic: false` — but they cannot be used with `LIKE` or pattern matching and are slower.

## Available collations vary between PostgreSQL releases

PostgreSQL imports its ICU collations from the ICU library it was built against, so the available set differs between PostgreSQL releases and between builds linked to different ICU versions. This library bundles a snapshot of the collation locales from PostgreSQL 17 (ICU 76) and resolves against it. Because resolution uses CLDR language matching rather than exact name lookup, small differences between the snapshot and your server are usually harmless — a locale matches the closest collation that exists in the snapshot, and base-language collations such as `de-x-icu` or `zh-x-icu` are present in every release.

To see exactly which ICU collations your server provides:

```sql
SELECT collname, colllocale
FROM pg_collation
WHERE collprovider = 'i'
ORDER BY collname;
```

If your server's set differs materially from the snapshot, pass your own list with the `:available` option of [Localize.Ecto.Collation.collation_for/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Collation.html#collation_for/2).

## Performance considerations

Linguistic comparison is more expensive than PostgreSQL's default byte-order comparison, and an `ORDER BY ... COLLATE` clause can only use an index that was created with the same collation. For hot queries, create an index with the collation you sort by using [Localize.Ecto.Migration.collated/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#collated/2):

```elixir
create index("products", [collated(:name, "de")])
```

If a PostgreSQL upgrade links a newer ICU library whose collation data changed — uncommon, but it happens — PostgreSQL warns of a collation version mismatch and indexes built with that collation must be reindexed. Nondeterministic collations carry an additional performance penalty. See the [PostgreSQL collation documentation](https://www.postgresql.org/docs/current/collation.html) for the details of collation selection, index compatibility, and the trade-offs between providers.

## Guides

* [Using Localize Ecto](https://hexdocs.pm/localize_ecto/using_localize_ecto.html) — the `collate/1,2` macros, locale resolution, and migrations.

* [Collations in PostgreSQL](https://hexdocs.pm/localize_ecto/collations_in_postgres.html) — how PostgreSQL collation works, choosing a database default, and how ICU collations relate to Localize.

* [Collations in SQLite](https://hexdocs.pm/localize_ecto/collations_in_sqlite.html) — the `localize_icu` extension, on-demand collation registration, and the trade-offs of indexing with an ICU collation.

## License

Copyright 2026 Kip Cole

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/elixir-localize/localize_ecto/blob/v0.3.0/LICENSE.md).

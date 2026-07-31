# Localize SQL

SQL database support for [Localize](https://hexdocs.pm/localize) and [Ecto](https://hexdocs.pm/ecto), in two parts: **locale-aware ICU collation** for query ordering, and **Ecto types** that store every Localize and relevant Elixir data type — money and units of measure with database-side aggregates, currencies, locales, territories, ranges, durations and more.

The first part resolves a Localize language tag to the best matching ICU collation and applies it with a `COLLATE` clause, so query results sort and compare according to the conventions of the user's locale:

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

The examples above are PostgreSQL. `Localize.Ecto` exposes the PostgreSQL macros directly; for SQLite, import [Localize.Ecto.SQLite3](https://hexdocs.pm/localize_sql/Localize.Ecto.SQLite3.html) instead — see [SQLite](#sqlite) below.

Locale resolution uses the [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching) algorithm, so any valid locale finds its best available collation — `"zh-TW"` resolves to `zh-Hant-x-icu`, `"de-DE"` to `de-x-icu`, and an unknown locale falls back gracefully. Locales that carry a BCP 47 collation type, such as `de-u-co-phonebk` (German phonebook order), resolve to collations you create once in a migration with [Localize.Ecto.Migration.create_collation/2](https://hexdocs.pm/localize_sql/Localize.Ecto.Migration.html#create_collation/2).

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

The [audit task](https://hexdocs.pm/localize_sql/Mix.Tasks.Localize.Ecto.Audit.html) reports collation version drift after PostgreSQL/ICU upgrades — with the `REINDEX` and `ALTER COLLATION … REFRESH VERSION` remediation for every dependent index — and compares the server's Unicode, ICU and time zone inventories against the application's:

```console
$ mix localize.ecto.audit
Audit for MyApp.Repo
  Collation versions: no drift
  Database default collation: no drift
  Server: PostgreSQL 17.4, Unicode 15.1, ICU Unicode 16.0
  Application: CLDR 48.2.2, Unicode 16.0
  Time zones: all application zones known to the server (100 server-only zones)
```

## Serializing Localize types

The second part is an `Ecto.Type` for every Localize and relevant Elixir data type, so a locale, a currency, a unit of measure or a range is a first-class value in a schema. Most store as ordinary text or `jsonb` and need no migration beyond the column:

```elixir
schema "listings" do
  field :locale,    Localize.LanguageTag.Ecto.Type   # text, e.g. "en-GB"
  field :currency,  Localize.Currency.Ecto.Type       # text, e.g. "USD"
  field :country,   Localize.Territory.Ecto.Type      # text, e.g. "US"
  field :levels,    Localize.Ecto.Type.IntegerRange   # int8range, e.g. 1..10
  field :period,    Localize.Ecto.Type.DateRange      # daterange
  field :retention, Localize.Ecto.Type.Duration       # interval
end
```

A value cast from user input is validated and canonicalized on the way in — an unknown currency or an invalid locale is rejected, and `"en_US"` becomes the resolved `"en-US"` language tag — and loaded back as the rich Localize value rather than the raw string.

### Money and units: database-side aggregates

A money amount or a unit of measure is a *tagged decimal* — a decimal paired with a tag (a currency code, a unit name) that is meaningless without it. `localize_sql` stores these as a PostgreSQL composite type and generates tag-guarded `sum`, `avg`, `min` and `max` aggregates and `+`/`-` operators, so the database itself refuses to add euros to yen or metres to feet:

```elixir
# in a migration
Localize.Unit.DDL.execute_each(Localize.Unit.DDL.create_cldr_unit())
Localize.Unit.DDL.execute_each(Localize.Unit.DDL.define_aggregate_functions())

# summing a column of like units works; mixing units raises in the database
Repo.aggregate(from(m in Measurement), :sum, :distance)
```

The same machinery, [Localize.Ecto.TaggedDecimal](https://hexdocs.pm/localize_sql/Localize.Ecto.TaggedDecimal.html), backs [ex_money_sql](https://hexdocs.pm/ex_money_sql), which builds its `money_with_currency` type and aggregates on `localize_sql` rather than defining its own.

| Type | Ecto type | Column |
|---|---|---|
| Currency | `Localize.Currency.Ecto.Type` | text |
| Language tag | `Localize.LanguageTag.Ecto.Type` | text |
| Territory / Script | `Localize.Territory.Ecto.Type` / `Localize.Script.Ecto.Type` | text |
| Time zone | `Localize.Ecto.Type.TimeZone` | text |
| Unit of measure | `Localize.Unit.Ecto.Composite.Type` (also `Map`, and the `WithUsage` variants) | composite / jsonb |
| Integer / date range | `Localize.Ecto.Type.IntegerRange` / `.DateRange` | int8range / daterange |
| Duration | `Localize.Duration.Ecto.Type` and `Localize.Ecto.Type.Duration` | interval |

The composite, range and duration types map to PostgreSQL types (via `postgrex`) and light up only when it is present; the text and `jsonb` types work on any Ecto adapter.

## Installation

Add `localize_sql` to your dependencies:

```elixir
def deps do
  [
    {:localize_sql, "~> 1.0"}
  ]
end
```

## SQLite

SQLite has no ICU collations of its own, so `localize_sql` ships one: `localize_icu`, a SQLite loadable extension that registers ICU collations under the same names PostgreSQL uses. The same locale resolves to the same collation name and produces the same ordering on either database, so a query ported between them sorts identically — the test suite asserts this for a range of languages and tailorings.

Install ICU (`brew install icu4c`, or `apt-get install libicu-dev`), enable the build in `config/config.exs`, and load the extension on every connection:

```elixir
# config/config.exs — read at compile time, so not runtime.exs
config :localize_sql, :sqlite_icu, true

# config/runtime.exs
config :my_app, MyApp.Repo,
  load_extensions: Localize.Ecto.SQLite3.Extension.load_extensions()
```

Then import [Localize.Ecto.SQLite3](https://hexdocs.pm/localize_sql/Localize.Ecto.SQLite3.html) in place of `Localize.Ecto`:

```elixir
import Ecto.Query
import Localize.Ecto.SQLite3

from p in Product, order_by: collate(p.name, "sv")

# No migration needed: SQLite collations are registered on demand
from p in Product, order_by: collate(p.name, "de-u-co-phonebk")
```

Collations are built the first time a query names one, so unlike PostgreSQL the BCP 47 tailorings — `-u-co-phonebk`, `-u-kn-true`, `-u-ks-level1` — need no `CREATE COLLATION` migration. The build is opt-in: without it `localize_sql` stays a pure-Elixir package needing no C toolchain or ICU, and PostgreSQL users are unaffected.

One consequence to weigh before indexing with an ICU collation: an index that names a collation makes the database unreadable by any connection that has not loaded the extension, including the `sqlite3` CLI. The [Collations in SQLite](https://hexdocs.pm/localize_sql/collations_in_sqlite.html) guide covers this, the case mapping differences, and what does not port from PostgreSQL.

## Deterministic collations and Unicode normalization

On PostgreSQL, the collations this library resolves to are deterministic, which is PostgreSQL's default. SQLite has no such concept and behaves differently here — see the end of this section. A deterministic collation never treats two strings as equal unless they are byte-for-byte identical: comparison first uses the linguistic collation order, then breaks ties bytewise. This has a practical consequence for Unicode text that is not normalized. Canonically equivalent strings in different normalization forms — for example `é` as the single code point U+00E9 versus `e` followed by combining U+0301 — will sort adjacently but will never compare equal, so equality tests, `DISTINCT`, `GROUP BY`, joins on text keys, and unique indexes all see them as different values.

To get expected results, normalize text (NFC is the usual choice) before writing it to the database. In Elixir use [String.normalize/2](https://hexdocs.pm/elixir/String.html#normalize/2); in PostgreSQL the [normalize](https://www.postgresql.org/docs/current/functions-string.html) function and `IS NFC NORMALIZED` predicate are available for checking or repairing existing data. Alternatively, PostgreSQL supports nondeterministic collations that do compare canonically equivalent strings as equal — [Localize.Ecto.Migration.create_collation/2](https://hexdocs.pm/localize_sql/Localize.Ecto.Migration.html#create_collation/2) can create one with `deterministic: false` — but they cannot be used with `LIKE` or pattern matching and are slower.

SQLite behaves as PostgreSQL's nondeterministic collations do, and it is the one place the two databases disagree. SQLite has no deterministic/nondeterministic distinction, so a comparison returns exactly what ICU says — and ICU treats canonically equivalent strings as equal. The NFC and NFD forms of `café` compare **equal** on SQLite and **unequal** on PostgreSQL. Ordering is unaffected on both, which is why sorting still agrees; it is equality, `DISTINCT`, `GROUP BY` and unique indexes that differ. Normalizing on write makes the question moot on either database, and is worth doing regardless.

## Available collations vary between PostgreSQL releases

PostgreSQL imports its ICU collations from the ICU library it was built against, so the available set differs between PostgreSQL releases and between builds linked to different ICU versions. This library bundles a snapshot of the collation locales from PostgreSQL 17 (ICU 76) and resolves against it. Because resolution uses CLDR language matching rather than exact name lookup, small differences between the snapshot and your server are usually harmless — a locale matches the closest collation that exists in the snapshot, and base-language collations such as `de-x-icu` or `zh-x-icu` are present in every release.

To see exactly which ICU collations your server provides:

```sql
SELECT collname, colllocale
FROM pg_collation
WHERE collprovider = 'i'
ORDER BY collname;
```

If your server's set differs materially from the snapshot, pass your own list with the `:available` option of [Localize.Ecto.Collation.collation_for/2](https://hexdocs.pm/localize_sql/Localize.Ecto.Collation.html#collation_for/2).

## Performance considerations

Linguistic comparison is more expensive than PostgreSQL's default byte-order comparison, and an `ORDER BY ... COLLATE` clause can only use an index that was created with the same collation. For hot queries, create an index with the collation you sort by using [Localize.Ecto.Migration.collated/2](https://hexdocs.pm/localize_sql/Localize.Ecto.Migration.html#collated/2):

```elixir
create index("products", [collated(:name, "de")])
```

If a PostgreSQL upgrade links a newer ICU library whose collation data changed — uncommon, but it happens — PostgreSQL warns of a collation version mismatch and indexes built with that collation must be reindexed. Nondeterministic collations carry an additional performance penalty. See the [PostgreSQL collation documentation](https://www.postgresql.org/docs/current/collation.html) for the details of collation selection, index compatibility, and the trade-offs between providers.

## Guides

* [Using Localize SQL](https://hexdocs.pm/localize_sql/using_localize_sql.html) — the `collate/1,2` macros, locale resolution, and migrations.

* [Collations in PostgreSQL](https://hexdocs.pm/localize_sql/collations_in_postgres.html) — how PostgreSQL collation works, choosing a database default, and how ICU collations relate to Localize.

* [Collations in SQLite](https://hexdocs.pm/localize_sql/collations_in_sqlite.html) — the `localize_icu` extension, on-demand collation registration, and the trade-offs of indexing with an ICU collation.

## License

Copyright 2026 Kip Cole

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/elixir-localize/localize_sql/blob/v1.0.0/LICENSE.md).

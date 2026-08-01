# Collations in PostgreSQL

Collation is the set of rules that determines how text sorts and compares. This guide explains how PostgreSQL handles collation, how its ICU collations relate to [Localize](https://hexdocs.pm/localize), and how to add collations PostgreSQL does not provide by default. The authoritative reference is the [PostgreSQL collation documentation](https://www.postgresql.org/docs/current/collation.html).

## The database default collation

Every PostgreSQL database has a default collation, fixed at `CREATE DATABASE` time, that applies to every text comparison and sort that does not name a collation explicitly. It also determines the behavior of case conversion (`upper`, `lower`, `ILIKE`) through its character-classification (ctype) side.

Our recommendation: make the database default a builtin code-point collation — `PG_UNICODE_FAST` on PostgreSQL 18 and later, `PG_C_UTF8` on PostgreSQL 17, `C` on earlier releases — and apply linguistic collation explicitly in queries with `COLLATE`, which is exactly what this library does.

* `PG_UNICODE_FAST` (provider `builtin`, PostgreSQL 18+) sorts in Unicode code-point order and applies *full* Unicode case mapping, including the mappings that change a string's length. This is the recommended default because it is the only PostgreSQL collation whose case conversion agrees with Elixir's: both `upper('ß')` in the database and `String.upcase("ß")` in application code return `"SS"`.

* `PG_C_UTF8` (provider `builtin`, PostgreSQL 17+) sorts identically, in code-point order, but applies *simple* one-to-one case mapping. `upper('ß')` returns `'ß'` unchanged, which disagrees with Elixir and with the Unicode default case conversion. Prefer it only on PostgreSQL 17, where `PG_UNICODE_FAST` is not yet available.

* `C` is the fallback for PostgreSQL 16 and earlier. Sorting is plain byte order, equally fast and stable, but its ctype is ASCII-only: `upper('öl')` returns `öL` with the `ö` untouched. Where you need case conversion on non-ASCII text, apply a collation to the expression — `upper('öl' COLLATE "de-x-icu")` returns `ÖL`.

All three sort text in the same order, and that order is also Elixir's. Erlang compares binaries byte by byte, and UTF-8 is designed so that byte order and code-point order coincide, so `Enum.sort/1` on a list of strings produces exactly the ordering a code-point database default produces:

```elixir
iex> Enum.sort(["a", "B", "ä", "Z", "_", "ß", "é"])
["B", "Z", "_", "a", "ß", "ä", "é"]
```

```sql
SELECT v FROM t ORDER BY v COLLATE "PG_UNICODE_FAST";
-- B, Z, _, a, ß, ä, é
```

That correspondence is the practical reason to keep the database default non-linguistic: a page of results ordered in SQL and the same page re-sorted in the BEAM agree, without either side having to know which collation the other used. Neither ordering is linguistically meaningful — `Zebra` precedes `apple` in both — so when you want human-facing order you opt into it explicitly on whichever side is doing the sorting: `COLLATE "sv-x-icu"` in the database, `Localize.Collation.sort/2` in Elixir. Those two agree with each other as well, because both implement UCA over the same CLDR data.

The choice between the three defaults is therefore entirely about case conversion, not about ordering or performance. Concretely:

| expression | `C` | `PG_C_UTF8` | `PG_UNICODE_FAST` | Elixir |
|---|---|---|---|---|
| `upper('ß')` | `ß` | `ß` | `SS` | `SS` |
| `upper('ﬁ')` | `ﬁ` | `ﬁ` | `FI` | `FI` |
| `lower('ΑΣ')` | `ΑΣ` | `ασ` | `ας` | `ας` |

Full case mapping has two consequences worth knowing before adopting it. `upper/1` can make a string longer, so a `varchar(n)` column sized against its input may overflow — `upper('ßßß')` is six characters, not three. And case conversion stops round-tripping: `lower(upper('ß'))` is `'ss'`, not `'ß'`. If you are using `upper/1` to compare case-insensitively, prefer a case-insensitive ICU collation for that comparison instead; that is what this library provides.

Changing the default collation of an existing database requires rebuilding indexes whose contents depend on it, including any functional index over `upper/1` or `lower/1`. On a new database the choice is free.

The reason for this recommendation is stability. A database default is fixed at `CREATE DATABASE` time, every index on text is built in its sort order, and a sort order that changes underneath an existing index silently corrupts the index's correctness. Each external collation provider carries exactly that risk:

* Operating system releases. A libc default such as `en_US.UTF-8` sorts according to the OS locale data, which changes with OS upgrades — the classic cause of index corruption after a glibc update.

* ICU releases. An ICU default would tie the database's sort order to the ICU library version, which changes as CLDR data evolves; PostgreSQL records collation versions and warns of mismatches, but the remedy is still reindexing the affected database. This applies to the explicit `COLLATE "…-x-icu"` expressions this library generates as well, and the two sides can end up a Unicode version apart, because the CLDR release Localize bundles and the ICU release a server links advance on separate schedules. They happen to agree today — Localize 1.0 ships CLDR 48, which is Unicode 17.0, and a PostgreSQL 18 build linked against ICU 77 is also Unicode 17.0 — but that is a coincidence of timing rather than a guarantee. `mix localize.ecto.audit` compares the two and reports any gap; a gap affects only characters added or re-weighted between those Unicode versions, so ordinary text orders identically on both sides.

* PostgreSQL releases. Byte order and code-point order are defined by Unicode itself, not by any library's tailoring data, so a `C`, `PG_C_UTF8` or `PG_UNICODE_FAST` default sorts identically across PostgreSQL upgrades and never demands a reindex on that account. One nuance: PostgreSQL versions the builtin collations (`collversion` is `1` today) because their *ctype* tracks the Unicode version PostgreSQL was built against, which advances with major releases — `SELECT unicode_version()` reports it. That can only affect case conversion, never sort order, so the exposure is limited to functional indexes over `upper/1` or `lower/1`. The `C` collation carries no version at all, since byte order cannot change.

Scoping linguistic collation to query expressions confines the versioned, changeable part of collation to the places that opt into it — and any index created with an explicit ICU collation (see `Localize.Ecto.Migration.collated/2`) is a known, listed object that can be reindexed deliberately when the ICU version moves.

None of these defaults sorts linguistically, and that is the point of the division of labor: the default collation keeps storage and indexes fast and stable, while queries opt into linguistic ordering per expression:

```elixir
from p in Product, order_by: collate(p.name, "sv")
```

### Setting the default

The default is fixed when the database is created and cannot be altered afterwards, so choose it at `CREATE DATABASE` time:

```sql
CREATE DATABASE my_app
  LOCALE_PROVIDER = builtin
  BUILTIN_LOCALE = 'PG_UNICODE_FAST'
  TEMPLATE = template0;
```

`TEMPLATE = template0` is required: `template1` carries its own collation, and PostgreSQL refuses to create a database with a different one from it. On PostgreSQL 17 substitute `BUILTIN_LOCALE = 'C.UTF-8'`; on 16 and earlier use `LC_COLLATE = 'C' LC_CTYPE = 'C'` and no provider clause.

To confirm what an existing database uses:

```sql
SELECT datname, datlocprovider, datlocale FROM pg_database WHERE datname = current_database();
-- my_app | b | PG_UNICODE_FAST
```

## Collation providers

PostgreSQL supports three collation providers:

* `libc` — the operating system's locale facilities. Availability and behavior vary by OS, and the sort order can change under you when the OS updates its locale data.

* `icu` — the [ICU library](https://icu.unicode.org), which implements the Unicode Collation Algorithm with the tailorings defined by [CLDR](https://cldr.unicode.org), the Unicode Common Locale Data Repository. ICU collations are consistent across operating systems and are versioned, so PostgreSQL can detect when a collation's underlying data has changed.

* `builtin` (PostgreSQL 17+) — PostgreSQL's own provider, with no external dependency and no exposure to OS or ICU upgrades. It offers `PG_C_UTF8` (code-point order, simple case mapping), `PG_UNICODE_FAST` (code-point order, full Unicode case mapping, PostgreSQL 18+) and `UCS_BASIC`. Because these are code-point collations, prefix `LIKE 'abc%'` uses a plain btree index without needing `text_pattern_ops`, exactly as under `C` — an ICU default would force a sequential scan there.

This library uses the ICU provider exclusively, and the relationship to Localize is direct: both draw on the same CLDR data. Localize implements CLDR locale identification, language matching, and (in `Localize.Collation`) the same UCA + CLDR collation rules in Elixir. That shared foundation means the ordering PostgreSQL produces for `COLLATE "sv-x-icu"` agrees with the ordering `Localize.Collation.sort/2` produces for locale `sv` in application code — the same names sort the same way in the database and in the BEAM.

## The default ICU collations and Localize language tags

When a PostgreSQL cluster is initialized, `initdb` imports a collation for every locale the linked ICU library provides, naming each after its BCP 47 locale identifier with an `-x-icu` suffix. The shapes you will find in `pg_collation`:

* A base collation per language: `de-x-icu`, `ja-x-icu`, `sv-x-icu`.

* Regional variants: `de-DE-x-icu`, `en-GB-x-icu`, `pt-BR-x-icu`. These exist for completeness but tailor nothing — CLDR collation rules are per language and script, so `de-DE-x-icu` and `de-x-icu` are the same collator.

* Script-qualified collations where a language is written in more than one script: `sr-Cyrl-x-icu` and `sr-Latn-x-icu`, `zh-Hans-x-icu` and `zh-Hant-x-icu`. For these languages there is no plain language-region name — Taiwan is `zh-Hant-TW-x-icu`, not `zh-TW-x-icu`.

* The root collation `und-x-icu`, the untailored Unicode default order.

Localize language tags map onto these names by [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching), not by string manipulation, which is what makes the mapping robust. A requested `zh-TW` matches `zh-Hant` (Traditional script is implied by the territory); `de-DE` matches `de`; an unmatchable locale falls back to `und`. The matching is against the canonical, unmaximalized locale identifier, so a requested `und` stays `und` rather than maximizing to `en`.

```elixir
iex> Localize.Ecto.Collation.collation_for!("zh-TW")
"zh-Hant-x-icu"

iex> Localize.Ecto.Collation.collation_for!("de-DE")
"de-x-icu"

iex> Localize.Ecto.Collation.collation_for!("sr")
"sr-x-icu"
```

The precise set of imported collations depends on the ICU version PostgreSQL was built against, and grows over time. Query your server with `SELECT collname, colllocale FROM pg_collation WHERE collprovider = 'i'` to see what you have.

## Defining collations with the migration functions

ICU can construct far more collators than PostgreSQL imports by default. Any BCP 47 locale with Unicode extension keywords is a valid collation definition, and `Localize.Ecto.Migration.create_collation/2` makes creating one a single, reversible migration step.

The most common case is a collation type — the `-u-co-` keyword — selecting an alternate ordering that CLDR defines for a language:

```elixir
def change do
  create_collation("de-u-co-phonebk")
end
```

This runs `CREATE COLLATION "de-u-co-phonebk-x-icu" (provider = icu, locale = 'de-u-co-phonebk')`. The name matches what `Localize.Ecto.Collation` resolves the locale to, so from then on `collate(p.name, "de-u-co-phonebk")` works with no further configuration. German phonebook order treats `ü` as `ue`: standard German sorts `Mueller, Muller, Müller` while phonebook order sorts `Mueller, Müller, Muller`. Other collation types include `zh-u-co-stroke` and `zh-u-co-zhuyin` for Chinese stroke and Bopomofo orderings, and `es-u-co-trad` for traditional Spanish, where `ch` sorts as a single letter.

Other ICU keywords open up collation behaviors beyond language tailoring. `Localize.Ecto.Migration.create_collation/2` accepts them as tailoring options using the `Localize.Collation.Options` vocabulary, and query-time resolution carries the same keywords, so the locale-with-keywords form works end to end without naming anything:

* Numeric ordering (`-u-kn`, option `numeric: true`) compares digit sequences by numeric value, giving natural sort: `file1, file2, file10` instead of `file1, file10, file2`.

  ```elixir
  # In a migration
  create_collation("en", numeric: true)

  # In queries — resolves to the collation created above
  from f in Upload, order_by: collate(f.name, "en-u-kn-true")
  ```

* Strength reduction (`-u-ks-level2`, option `strength: :secondary`) ignores case differences; `strength: :primary` ignores accents too. These strengths default to a nondeterministic collation — the only mode in which `'HELLO' = 'hello'` is actually true — giving case-insensitive matching without `citext` or `lower()` wrappers, at the cost that `LIKE` and pattern matching cannot use the collation (PostgreSQL 18 lifts the `LIKE` restriction). A unique index over such a collation enforces case-insensitive uniqueness:

  ```elixir
  create_collation("und", strength: :secondary)
  create index("users", [collated(:email, "und-u-ks-level2")], unique: true)
  ```

Custom-named collations are used in queries with the `:collation` option:

```elixir
create_collation("und", numeric: true, name: "natural_sort")
from f in Upload, order_by: collate(f.name, collation: "natural_sort")
```

Two practical notes. PostgreSQL normalizes ICU locale identifiers when it stores them (`und-u-kn-true` is recorded as `und-u-kn`), which can produce a server notice at creation time — harmless, and the collation's name is unaffected. And because collations live in the database, remember that a collation created in a migration exists per database: test, dev, and production each get theirs when migrations run.

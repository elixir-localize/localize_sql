# Localize SQL usage rules

Rules for LLM coding agents using `localize_sql` as a dependency. Not exhaustive — see the HexDocs guides for full reference.

## What this package is for

Persisting and querying Localize's data types in a database: Ecto types for them, locale-aware `COLLATE` for PostgreSQL and SQLite, and PostgreSQL composite types with tag-guarded `sum`/`avg`/`min`/`max` aggregates for money and units of measure.

Built on [`localize`](https://hex.pm/packages/localize).

## Core conventions

* Use the provided Ecto types in your schemas rather than storing a formatted string. A formatted value is for a reader in one locale at one moment; the underlying value is what belongs in a column.

* Unit and money columns are composite types carrying both the magnitude and its tag (the unit or currency). The aggregates are *tag-guarded*: summing across different units or currencies raises rather than returning a meaningless number.

* Migrations that create the composite types and aggregate functions live in `Localize.Unit.DDL` — `create_cldr_unit/1`, `define_aggregate_functions/1` and their `drop_*` counterparts.

## Things not to do

* **Do not sort user-visible text with plain `ORDER BY`.** The database's default collation is not the user's locale, and the result will be wrong for anything outside ASCII. Use the locale-aware `COLLATE` this package provides.

* Do not store money as a bare `numeric` with the currency in a separate column and sum it. Nothing stops the sum crossing currencies. Use the composite type and its guarded aggregate.

* Do not store a formatted number, date or money string in the database. Store the value; format on the way out, for the reader.

* Do not assume PostgreSQL. The collation support covers SQLite as well, through the `localize_icu` loadable extension, with asserted ordering parity between the two.

* Do not hand-write the composite type DDL. Use `Localize.Unit.DDL` so the shape matches what the Ecto types expect.

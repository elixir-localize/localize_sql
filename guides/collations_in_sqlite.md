# Collations in SQLite

SQLite ships three collating sequences: `BINARY` (code point order), `NOCASE` (ASCII case folding only) and `RTRIM`. None of them sorts linguistically, and SQLite has no equivalent of PostgreSQL's ICU provider. This guide explains how `localize_ecto` adds ICU collation to SQLite, how it stays compatible with the PostgreSQL side of the library, and the operational consequences of using it.

## The localize_icu extension

`localize_ecto` ships a SQLite loadable extension, `localize_icu`, that links against [ICU](https://icu.unicode.org) and registers collations under the names PostgreSQL uses — `de-x-icu`, `sv-x-icu`, `zh-Hant-TW-x-icu`, `und-x-icu`. Because both databases now reach ICU through the same two calls — `uloc_forLanguageTag()` to turn the BCP 47 tag into an ICU locale, then `ucol_open()` — the same locale produces the same collation name and the same ordering on either database.

A loadable extension is the mechanism SQLite provides for this, and it is the mechanism SQLite's own [ICU extension](https://sqlite.org/src/dir/ext/icu) uses. SQLite opens the shared library itself and hands the entry point the database connection along with a table of API function pointers, so the extension never links against SQLite. A NIF cannot take its place: registering a collation needs the `sqlite3 *` connection handle, which the driver owns privately and does not expose.

## Registration is lazy, and needs no migration

The extension installs a [`sqlite3_collation_needed`](https://sqlite.org/c3ref/collation_needed.html) handler rather than registering hundreds of collations up front. When a statement names a collation the connection does not have, SQLite calls the handler, which builds that one collation from its name and registers it. Nothing is built until a query asks for it.

This removes the asymmetry that exists on the PostgreSQL side. PostgreSQL preloads a collation for every locale its ICU library knows, but only for plain locales — anything carrying a BCP 47 collation type or tailoring keyword needs `CREATE COLLATION` in a migration first. On SQLite there is nothing to create:

```elixir
import Localize.Ecto.SQLite3

# Works with no migration, no DDL, no setup beyond loading the extension
from p in Product, order_by: collate(p.name, "de-u-co-phonebk")
from f in Upload, order_by: collate(f.name, "en-u-kn-true")
from u in User, order_by: collate(u.email, "und-u-ks-level1")
```

The reason is structural: a SQLite collation is a per-connection runtime registration, not a schema object. It lives in the connection, not in the database file. That is also why every connection in a pool has to load the extension, which is what `:load_extensions` does.

## Setup

The extension needs a C compiler and the ICU development libraries, which PostgreSQL-only users have no reason to install, so it is not built unless you ask for it.

Install ICU — `brew install icu4c` on macOS, `apt-get install libicu-dev` on Debian or Ubuntu — then enable the build in `config/config.exs`:

```elixir
config :localize_ecto, :sqlite_icu, true
```

The key must be in `config.exs` rather than `runtime.exs`, because it is read at compile time to decide whether to run the C build. Setting `LOCALIZE_ECTO_SQLITE_ICU=true` in the environment does the same thing.

Then load the extension on every connection. Both `Exqlite` and `Ecto.Adapters.SQLite3` accept `:load_extensions` and apply it to each pooled connection:

```elixir
# config/runtime.exs
config :my_app, MyApp.Repo,
  database: "my_app.sqlite3",
  load_extensions: Localize.Ecto.SQLite3.Extension.load_extensions()
```

[Localize.Ecto.SQLite3.Extension.load_extensions/0](https://hexdocs.pm/localize_ecto/Localize.Ecto.SQLite3.Extension.html#load_extensions/0) returns an empty list when the extension was not built, so the same configuration is safe in an environment that has not opted in.

## An indexed database depends on the extension

This is the one consequence worth deciding about before you start.

If you create an index with an ICU collation, that collation becomes part of the database's schema. SQLite must resolve it whenever it parses a statement against the table, so any connection that has not loaded `localize_icu` fails with `no such collation sequence` — not only for queries that mention the collation, but for ordinary reads and writes to that table. That includes the `sqlite3` command line tool, `.dump`, and any other program that opens the file.

```elixir
# After this, the database requires localize_icu to be readable
create index("products", [collated(:name, "de")])
```

The trade-off is the same one PostgreSQL presents with `CREATE INDEX ... COLLATE`, except that PostgreSQL keeps the collation in the database while SQLite keeps it in the connection. If portability of the database file matters more than index-backed ordering, collate in the query and leave the index on the default `BINARY` collation. Ordering still works — it just sorts without an index.

For the same reason, `ATTACH`ing such a database or restoring it on a machine without a matching ICU build needs the extension present first.

## Case mapping is separate from collation

In PostgreSQL, `lower()`, `upper()` and `initcap()` take their case mapping from the collation of their argument, so `lower(name COLLATE "tr-x-icu")` produces the Turkish dotless `ı`. SQLite's `COLLATE` affects comparison only and never case mapping, and its built-in `lower()` and `upper()` map ASCII exclusively — `upper('é')` is `é`.

The extension therefore registers two-argument `upper(X, locale)`, `lower(X, locale)` and `title(X, locale)` functions that map case with ICU. Only the two-argument forms are registered; SQLite dispatches on arity, so the one-argument built-ins keep their existing behaviour and nothing else in your application changes.

`Localize.Ecto.SQLite3` expands to these automatically, and keeps PostgreSQL's `initcap` name so queries port unchanged:

```elixir
from p in Product, select: lower(p.name, "tr")      # lower(name, 'tr-x-icu')
from p in Product, select: initcap(p.name, "nl")    # title(name, 'nl-x-icu')
```

## Strength, case and accent insensitivity

SQLite has no equivalent of PostgreSQL's deterministic and nondeterministic collations, and does not need one. A collation that compares `"cafe"` and `"café"` as equal simply is that collation, and it works in `ORDER BY`, `=`, `GROUP BY`, `DISTINCT` and unique indexes alike:

```elixir
# Case- and accent-insensitive uniqueness, no citext, no migration
create unique_index("users", [collated(:email, "und-u-ks-level1")])
```

This is one place SQLite is simpler than PostgreSQL, where the same behaviour needs a nondeterministic collation that then cannot be used with `LIKE` or `pg_trgm`. SQLite's `LIKE` ignores collations entirely, so it is unaffected either way.

## ICU versions

Collation data changes as CLDR evolves, so an ordering is only reproducible across machines that link comparable ICU versions. PostgreSQL records the collation version it created each collation with and warns when the underlying data has moved; SQLite records nothing, because it has nothing to record — the collation is rebuilt from its name on every connection.

In practice this means two things. Indexes built with an ICU collation should be rebuilt if the ICU library under the extension changes materially, exactly as PostgreSQL requires a `REINDEX` after a collation version change. And if you rely on PostgreSQL and SQLite agreeing exactly — the library's test suite asserts this for a range of languages and tailorings — the two need ICU versions whose collation data agrees. The `mix localize.ecto.audit` task reports the PostgreSQL side; for the extension, `otool -L` or `ldd` on the built library shows which ICU it linked.

## What does not port

Three things in `Localize.Ecto.Postgres` have no SQLite counterpart:

* [Localize.Ecto.Migration.create_collation/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#create_collation/2) — there is nothing to create, as described above. [Localize.Ecto.Migration.collated/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#collated/2) does work on both and is what you use for indexes.

* `at_time_zone/2` — SQLite has no time zone support and no timestamp type to apply one to.

* `ts_match/2,3` — SQLite's full-text search is FTS5, which indexes a virtual table rather than evaluating an expression over an ordinary column. It is a genuinely different shape and is not wrapped by this library.

* [Localize.Ecto.Audit](https://hexdocs.pm/localize_ecto/Localize.Ecto.Audit.html) and `mix localize.ecto.audit` are PostgreSQL-only, since SQLite stores no collation versions to drift.

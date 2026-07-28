defmodule Localize.Ecto.SQLite3 do
  @moduledoc """
  Locale-aware query expressions for Ecto on SQLite.

  The macros mirror `Localize.Ecto.Postgres` and resolve collation names
  through the same `Localize.Ecto.Collation.resolve!/1`, so a locale
  produces the same collation name — `"de-x-icu"`, `"sv-x-icu"`,
  `"de-u-co-phonebk-x-icu"` — on both databases and a query ported
  between them sorts identically.

  SQLite has no ICU collations of its own, so these macros require the
  `localize_icu` extension this library ships. It is opt-in at build
  time and loaded on every pooled connection:

      # mix.exs, or LOCALIZE_ECTO_SQLITE_ICU=true when compiling
      config :localize_ecto, :sqlite_icu, true

      # config/runtime.exs
      config :my_app, MyApp.Repo,
        load_extensions: Localize.Ecto.SQLite3.Extension.load_extensions()

  See `Localize.Ecto.SQLite3.Extension` and the
  [Collations in SQLite](collations_in_sqlite.html) guide for the full
  setup, including what happens to a database indexed with an ICU
  collation when the extension is absent.

  With the extension loaded, usage is the same as on PostgreSQL:

      import Ecto.Query
      import Localize.Ecto.SQLite3

      from p in Product, order_by: collate(p.name, "sv")

      from p in Product, where: collate(p.name < "münchen", "de"), select: p.name

  Unlike PostgreSQL, collations carrying a BCP 47 collation type need
  no migration. SQLite collations are per-connection runtime
  registrations rather than schema objects, and the extension builds
  each one the first time a statement names it, so
  `collate(p.name, "de-u-co-phonebk")` works with no setup beyond
  loading the extension.

  ### Differences from PostgreSQL

  * `lower/2`, `upper/2` and `initcap/2` expand to the ICU functions the
    extension registers, not to a collated argument. SQLite's `COLLATE`
    affects comparison only and never case mapping, and SQLite has no
    `initcap` — it is `title()` here.

  * `Localize.Ecto.Postgres.at_time_zone/2` and
    `Localize.Ecto.Postgres.ts_match/2,3` have no SQLite counterpart.
    SQLite has no time zone support, and its full-text search is FTS5,
    which needs a virtual table per searched column rather than an
    expression over an ordinary column.

  * `Localize.Ecto.Migration.create_collation/2` is PostgreSQL-only, as
    described above. `Localize.Ecto.Migration.collated/2` emits valid
    SQLite index syntax and works on both.

  * Canonically equivalent strings compare *equal* here and *unequal* on
    PostgreSQL. SQLite has no deterministic collations, so a comparison
    returns what ICU says, and ICU considers the NFC and NFD forms of
    `café` the same string; PostgreSQL breaks that tie bytewise.
    Ordering agrees on both — it is equality, `DISTINCT`, `GROUP BY` and
    unique indexes that differ. Normalizing on write removes the
    difference.

  """

  alias Localize.Ecto.Builder

  @doc """
  Applies a `COLLATE` clause for the current locale.

  The collation is resolved from `Localize.get_locale/0` at the time
  the query is built.

  ### Arguments

  * `expression` is any Ecto query expression that evaluates to a
    string value, or a comparison (`<`, `<=`, `>`, `>=`, `==`, `!=`)
    between two such expressions.

  ### Returns

  * A query fragment `expression COLLATE "collation"`, or for a
    comparison `left OP right COLLATE "collation"`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", order_by: collate(p.name), select: p.name
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro collate(expression) do
    Builder.collate(expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Applies a `COLLATE` clause for the given locale or collation.

  ### Arguments

  * `expression` is any Ecto query expression that evaluates to a
    string value, or a comparison (`<`, `<=`, `>`, `>=`, `==`, `!=`)
    between two such expressions.

  * `locale_or_options` is a `t:Localize.LanguageTag.t/0`, any locale
    identifier accepted by `Localize.validate_locale/1`, or a keyword
    list of options. A pinned expression (`^locale`) is also accepted,
    so runtime locale values read naturally in query syntax.

  ### Options

  * `:collation` is a collation name used verbatim, bypassing locale
    resolution. On SQLite the name is itself the BCP 47 tag, so this is
    mainly useful for names produced elsewhere.

  * Any other options are passed to
    `Localize.Ecto.Collation.collation_for!/2`.

  ### Returns

  * A query fragment `expression COLLATE "collation"`, or for a
    comparison `left OP right COLLATE "collation"`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", order_by: collate(p.name, "sv"), select: p.name
      iex> match?(%Ecto.Query{}, query)
      true

      iex> import Ecto.Query
      iex> query = from p in "products", select: collate(p.name < p.description, "de")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro collate(expression, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    Builder.collate(
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  @doc """
  Locale-aware `lower()` using the current locale.

  See `lower/2`.
  """
  defmacro lower(expression) do
    Builder.sqlite_case(:lower, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `lower()`.

  Expands to the two-argument `lower(expression, locale)` the `localize_icu` extension registers, which maps case with ICU for the locale — under Turkish, `lower("I")` is the dotless "ı". SQLite's one-argument `lower()` is unaffected and still maps ASCII only.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  * `locale_or_options` is a locale or keyword list as accepted by `collate/2`. A pinned expression (`^locale`) is also accepted.

  ### Returns

  * A query fragment `lower(expression, 'collation')`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: lower(p.name, "tr")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro lower(expression, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    Builder.sqlite_case(
      :lower,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  @doc """
  Locale-aware `upper()` using the current locale.

  See `lower/2`.
  """
  defmacro upper(expression) do
    Builder.sqlite_case(:upper, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `upper()`. See `lower/2` for the arguments and semantics.
  """
  defmacro upper(expression, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    Builder.sqlite_case(
      :upper,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  @doc """
  Locale-aware title casing using the current locale.

  See `initcap/2`.
  """
  defmacro initcap(expression) do
    Builder.sqlite_case(:title, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware title casing, the equivalent of PostgreSQL's `initcap()`.

  Expands to the `title(expression, locale)` function the `localize_icu` extension registers. SQLite has no `initcap`; the macro keeps the PostgreSQL name so queries port unchanged. See `lower/2` for the arguments and semantics.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: initcap(p.name, "nl")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro initcap(expression, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    Builder.sqlite_case(
      :title,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end
end

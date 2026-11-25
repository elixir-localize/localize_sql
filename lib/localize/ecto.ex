defmodule Localize.Ecto do
  @moduledoc """
  Locale-aware query expressions for Ecto.

  Text sorts differently in different languages, and neither PostgreSQL
  nor SQLite sorts linguistically unless a query asks it to. This
  library resolves a [Localize](https://hexdocs.pm/localize) language
  tag to an ICU collation and applies it to a query expression, so that
  ordering, comparison and case mapping follow the user's locale.

  There is one module per database, because Ecto requires the SQL of a
  fragment to be a compile-time literal and the two databases do not
  spell everything the same way:

  * `Localize.Ecto.Postgres` — PostgreSQL. `collate/1,2`, `lower/1,2`,
    `upper/1,2`, `initcap/1,2`, plus `at_time_zone/2` and `ts_match/2,3`.

  * `Localize.Ecto.SQLite3` — SQLite, via the `localize_icu` extension
    this library ships. `collate/1,2`, `lower/1,2`, `upper/1,2` and
    `initcap/1,2`.

  Both resolve collation names through the same
  `Localize.Ecto.Collation`, so a locale produces the same name —
  `"de-x-icu"`, `"sv-x-icu"`, `"de-u-co-phonebk-x-icu"` — on either
  database and a query written for one sorts identically on the other.

  This module exposes the PostgreSQL macros directly, so existing code
  that imports it keeps working and PostgreSQL users need not think
  about the split:

      import Ecto.Query
      import Localize.Ecto

      # Collate using the current locale (Localize.get_locale/0)
      from p in Product, order_by: collate(p.name)

      # Collate using an explicit locale
      from p in Product, order_by: collate(p.name, "sv")

      # Locale determined at runtime
      def sorted_products(locale) do
        from p in Product, order_by: collate(p.name, ^locale)
      end

      # Collate a comparison: name < 'münchen' under German collation
      from p in Product, where: collate(p.name < "münchen", "de"), select: p.name

      # Use a collation created in a migration, by name
      from p in Product, order_by: collate(p.name, collation: "german_phonebook")

  For SQLite, import `Localize.Ecto.SQLite3` instead. An application
  talking to both databases imports each where it needs it.

  Collations for locales carrying a BCP 47 collation type, such as
  `de-u-co-phonebk`, are not preloaded by PostgreSQL. Create them once
  in a migration with `Localize.Ecto.Migration.create_collation/2` and
  they resolve automatically thereafter. SQLite needs no such migration.

  """

  alias Localize.Ecto.Builder

  @doc """
  Applies a `COLLATE` clause for the current locale.

  The collation is resolved from `Localize.get_locale/0` at the time
  the query is built.

  This is `Localize.Ecto.Postgres.collate/1`, exposed here for backwards compatibility.

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

  This is `Localize.Ecto.Postgres.collate/2`, exposed here for backwards compatibility.

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
    resolution — for example a collation created with
    `Localize.Ecto.Migration.create_collation/2` under a custom name.

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
  Applies PostgreSQL's `AT TIME ZONE` with a validated time zone.

  The zone is canonicalized by `Localize.Ecto.Type.TimeZone.canonicalize!/1` when the query is built, so an alias or BCP 47 short zone identifier is accepted and an unknown zone raises in the application instead of failing on the server.

  This is `Localize.Ecto.Postgres.at_time_zone/2`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a timestamp.

  * `zone` is a canonical IANA name, a CLDR-known alias, or a BCP 47 short zone identifier. A pinned expression (`^zone`) is also accepted.

  ### Returns

  * A query fragment `expression AT TIME ZONE 'zone'`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from e in "events", select: at_time_zone(e.starts_at, "Australia/Sydney")
      iex> match?(%Ecto.Query{}, query)
      true


  """
  defmacro at_time_zone(expression, zone) do
    zone = Builder.unpin(zone)

    quote do
      fragment(
        "? AT TIME ZONE ?",
        unquote(expression),
        ^Localize.Ecto.Type.TimeZone.canonicalize!(unquote(zone))
      )
    end
  end

  @doc """
  Locale-aware full-text search match using the current locale.

  The text search configuration is resolved from `Localize.get_locale/0` when the query is built. See `ts_match/3`.

  This is `Localize.Ecto.Postgres.ts_match/2`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to the searched text.

  * `query` is the user's search input, in `websearch_to_tsquery` syntax.

  ### Returns

  * A boolean query fragment for use in `where`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", where: ts_match(p.description, "wooden chair"), select: p.id
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro ts_match(expression, query) do
    build_ts_match(expression, query, quote(do: Localize.Ecto.TextSearch.config_for!()))
  end

  @doc """
  Locale-aware full-text search match.

  Expands to `to_tsvector(config, expression) @@ websearch_to_tsquery(config, query)` where `config` is the PostgreSQL text search configuration `Localize.Ecto.TextSearch.config_for!/2` resolves for the locale — `'german'` for `"de-AT"`, `'simple'` for languages PostgreSQL has no stemmer for.

  This is `Localize.Ecto.Postgres.ts_match/3`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to the searched text.

  * `query` is the user's search input, in `websearch_to_tsquery` syntax.

  * `locale_or_options` is a locale accepted by `Localize.Ecto.TextSearch.config_for!/2`, or a keyword list with a `:config` option naming a text search configuration directly. A pinned expression (`^locale`) is also accepted.

  ### Returns

  * A boolean query fragment for use in `where`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", where: ts_match(p.description, "wooden chair", "de"), select: p.id
      iex> match?(%Ecto.Query{}, query)
      true


  """
  defmacro ts_match(expression, query, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    resolver =
      quote do
        case unquote(locale_or_options) do
          options when is_list(options) ->
            case Keyword.pop(options, :config) do
              {nil, options} ->
                Localize.Ecto.TextSearch.config_for!(Localize.get_locale(), options)

              {config, _options} ->
                config
            end

          locale ->
            Localize.Ecto.TextSearch.config_for!(locale)
        end
      end

    build_ts_match(expression, query, resolver)
  end

  # The configuration is bound as a text parameter and cast to
  # regconfig on the server — postgrex encodes a bare `?::regconfig`
  # parameter as an oid, not a name.
  defp build_ts_match(expression, query, resolver) do
    quote do
      fragment(
        "to_tsvector(?::text::regconfig, ?) @@ websearch_to_tsquery(?::text::regconfig, ?)",
        ^unquote(resolver),
        unquote(expression),
        ^unquote(resolver),
        unquote(query)
      )
    end
  end

  @doc """
  Locale-aware `lower()` using the collation of the current locale.

  The collation is resolved from `Localize.get_locale/0` when the query is built. See `lower/2` for how the collation determines the case mapping.

  This is `Localize.Ecto.Postgres.lower/1`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  ### Returns

  * A query fragment `lower(expression COLLATE "collation")`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: lower(p.name)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro lower(expression) do
    Builder.postgres_case(:lower, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `lower()`.

  PostgreSQL's `lower()`, `upper()` and `initcap()` follow the collation of their argument, so the locale determines the case mapping — under a Turkish collation `lower("I")` is the dotless "ı", which the default collation gets wrong.

  This is `Localize.Ecto.Postgres.lower/2`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  * `locale_or_options` is a locale or keyword list as accepted by `collate/2`. A pinned expression (`^locale`) is also accepted.

  ### Returns

  * A query fragment `lower(expression COLLATE "collation")`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: lower(p.name, "tr")
      iex> match?(%Ecto.Query{}, query)
      true


  """
  defmacro lower(expression, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    Builder.postgres_case(
      :lower,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  @doc """
  Locale-aware `upper()` using the collation of the current locale.

  The collation is resolved from `Localize.get_locale/0` when the query is built. See `upper/2` for how the collation determines the case mapping.

  This is `Localize.Ecto.Postgres.upper/1`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  ### Returns

  * A query fragment `upper(expression COLLATE "collation")`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: upper(p.name)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro upper(expression) do
    Builder.postgres_case(:upper, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `upper()`.

  Under a Turkish collation `upper("i")` is the dotted "İ". See `lower/2` for how the collation determines the case mapping.

  This is `Localize.Ecto.Postgres.upper/2`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  * `locale_or_options` is a locale or keyword list as accepted by `collate/2`. A pinned expression (`^locale`) is also accepted.

  ### Returns

  * A query fragment `upper(expression COLLATE "collation")`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: upper(p.name, "tr")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro upper(expression, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    Builder.postgres_case(
      :upper,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  @doc """
  Locale-aware `initcap()` using the collation of the current locale.

  The collation is resolved from `Localize.get_locale/0` when the query is built. See `initcap/2` for how the collation determines the case mapping.

  This is `Localize.Ecto.Postgres.initcap/1`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  ### Returns

  * A query fragment `initcap(expression COLLATE "collation")`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: initcap(p.name)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro initcap(expression) do
    Builder.postgres_case(:initcap, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `initcap()`.

  Each word's first letter is upper-cased and the rest lower-cased, by the locale's rules. See `lower/2` for how the collation determines the case mapping.

  This is `Localize.Ecto.Postgres.initcap/2`, exposed here for backwards compatibility.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  * `locale_or_options` is a locale or keyword list as accepted by `collate/2`. A pinned expression (`^locale`) is also accepted.

  ### Returns

  * A query fragment `initcap(expression COLLATE "collation")`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: initcap(p.name, "nl")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro initcap(expression, locale_or_options) do
    locale_or_options = Builder.unpin(locale_or_options)

    Builder.postgres_case(
      :initcap,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end
end

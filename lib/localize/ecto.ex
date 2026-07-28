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

  See `Localize.Ecto.Postgres.collate/1`.

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

  See `Localize.Ecto.Postgres.collate/2`.

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

  See `Localize.Ecto.Postgres.at_time_zone/2`.

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

  See `Localize.Ecto.Postgres.ts_match/2`.
  """
  defmacro ts_match(expression, query) do
    build_ts_match(expression, query, quote(do: Localize.Ecto.TextSearch.config_for!()))
  end

  @doc """
  Locale-aware full-text search match.

  See `Localize.Ecto.Postgres.ts_match/3`.

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

  See `Localize.Ecto.Postgres.lower/1`.
  """
  defmacro lower(expression) do
    Builder.postgres_case(:lower, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `lower()`.

  See `Localize.Ecto.Postgres.lower/2`.

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

  See `Localize.Ecto.Postgres.upper/1`.
  """
  defmacro upper(expression) do
    Builder.postgres_case(:upper, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `upper()`.

  See `Localize.Ecto.Postgres.upper/2`.
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

  See `Localize.Ecto.Postgres.initcap/1`.
  """
  defmacro initcap(expression) do
    Builder.postgres_case(:initcap, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `initcap()`.

  See `Localize.Ecto.Postgres.initcap/2`.
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

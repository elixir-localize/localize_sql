defmodule Localize.Ecto.SQLite3Test do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Localize.Ecto.SQLite3

  require Localize.Ecto.Postgres

  doctest Localize.Ecto.SQLite3

  defp to_sql(query) do
    {query, _cast_params, _dump_params} =
      Ecto.Adapter.Queryable.plan_query(:all, Ecto.Adapters.SQLite3, query)

    IO.iodata_to_binary(Ecto.Adapters.SQLite3.Connection.all(query))
  end

  describe "collate/1,2" do
    test "emits a COLLATE clause with the quoted collation name" do
      query = from p in "products", order_by: collate(p.name, "sv"), select: p.name

      assert to_sql(query) =~ ~s[ORDER BY p0."name" COLLATE "sv-x-icu"]
    end

    test "resolves the current locale when no locale is given" do
      query = from p in "products", order_by: collate(p.name), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "en-x-icu"]
    end

    test "carries a BCP 47 collation type into the name" do
      query = from p in "products", order_by: collate(p.name, "de-u-co-phonebk"), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "de-u-co-phonebk-x-icu"]
    end

    test "collates a comparison" do
      query = from p in "products", where: collate(p.name < "münchen", "de"), select: p.name

      assert to_sql(query) =~ ~s[WHERE (p0."name" < 'münchen' COLLATE "de-x-icu")]
    end

    test "accepts a runtime locale" do
      locale = "sv"
      query = from p in "products", order_by: collate(p.name, ^locale), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "sv-x-icu"]
    end

    test "accepts a collation name directly" do
      query = from p in "products", order_by: collate(p.name, collation: "custom"), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "custom"]
    end

    # The compatibility guarantee: the same locale must produce the same
    # collation name on both adapters, so a query ported between them
    # names the same collation.
    test "emits the same collation name as the PostgreSQL macros" do
      for locale <- ["de", "de-AT", "sv", "zh-TW", "und", "de-u-co-phonebk"] do
        sqlite =
          from(p in "products", order_by: collate(p.name, ^locale), select: p.name) |> to_sql()

        postgres =
          from(p in "products",
            order_by: Localize.Ecto.Postgres.collate(p.name, ^locale),
            select: p.name
          )
          |> postgres_sql()

        assert collation_in(sqlite) == collation_in(postgres),
               "#{locale}: SQLite named #{collation_in(sqlite)}, " <>
                 "PostgreSQL named #{collation_in(postgres)}"
      end
    end
  end

  defp postgres_sql(query) do
    {query, _cast_params, _dump_params} =
      Ecto.Adapter.Queryable.plan_query(:all, Ecto.Adapters.Postgres, query)

    IO.iodata_to_binary(Ecto.Adapters.Postgres.Connection.all(query))
  end

  defp collation_in(sql) do
    [_match, collation] = Regex.run(~r/COLLATE "([^"]+)"/, sql)
    collation
  end

  describe "case mapping" do
    # SQLite's COLLATE never affects case mapping, so these expand to
    # the extension's two-argument ICU functions with the locale bound
    # as a parameter rather than emitted as an identifier.
    test "lower/2 calls the two-argument ICU function" do
      query = from p in "products", select: lower(p.name, "tr")

      assert to_sql(query) =~ ~s[SELECT lower(p0."name", ?)]
    end

    test "upper/2 calls the two-argument ICU function" do
      query = from p in "products", select: upper(p.name, "tr")

      assert to_sql(query) =~ ~s[SELECT upper(p0."name", ?)]
    end

    test "initcap/2 maps to the extension's title function" do
      query = from p in "products", select: initcap(p.name, "nl")

      assert to_sql(query) =~ ~s[SELECT title(p0."name", ?)]
    end

    test "the one-argument forms resolve the current locale" do
      query = from p in "products", select: lower(p.name)

      assert to_sql(query) =~ ~s[SELECT lower(p0."name", ?)]
    end
  end
end

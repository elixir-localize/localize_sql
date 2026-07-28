defmodule Localize.Ecto.PostgresTest do
  # `Localize.Ecto` exposes the same macros for backwards compatibility
  # and is covered by test/localize/ecto_test.exs. This suite drives
  # Localize.Ecto.Postgres directly so the named adapter module is
  # exercised on its own terms rather than by inference from the alias.
  use ExUnit.Case, async: true

  import Ecto.Query
  import Localize.Ecto.Postgres

  require Localize.Ecto

  doctest Localize.Ecto.Postgres

  defp to_sql(query) do
    {query, _cast_params, _dump_params} =
      Ecto.Adapter.Queryable.plan_query(:all, Ecto.Adapters.Postgres, query)

    IO.iodata_to_binary(Ecto.Adapters.Postgres.Connection.all(query))
  end

  describe "collate/1,2" do
    test "collate/1 resolves the current locale" do
      query = from p in "products", order_by: collate(p.name), select: p.name

      assert to_sql(query) =~ ~s[ORDER BY p0."name" COLLATE "en-x-icu"]
    end

    test "collate/2 emits the quoted collation name" do
      query = from p in "products", order_by: collate(p.name, "sv"), select: p.name

      assert to_sql(query) =~ ~s[ORDER BY p0."name" COLLATE "sv-x-icu"]
    end

    test "accepts a pinned runtime locale" do
      locale = "de-DE"
      query = from p in "products", order_by: collate(p.name, ^locale), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "de-x-icu"]
    end

    test "accepts a collation name given directly" do
      query =
        from p in "products",
          order_by: collate(p.name, collation: "german_phonebook"),
          select: p.name

      assert to_sql(query) =~ ~s[COLLATE "german_phonebook"]
    end

    test "carries a BCP 47 collation type into the name" do
      query = from p in "products", order_by: collate(p.name, "de-u-co-phonebk"), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "de-u-co-phonebk-x-icu"]
    end

    test "collates a comparison" do
      query = from p in "products", where: collate(p.name < "münchen", "de"), select: p.name

      assert to_sql(query) =~ ~s[WHERE (p0."name" < 'münchen' COLLATE "de-x-icu")]
    end

    test "collates each comparison operator" do
      equality = from p in "products", select: collate(p.name == p.description, "de")
      inequality = from p in "products", select: collate(p.name != p.description, "de")
      greater = from p in "products", select: collate(p.name >= p.description, "de")

      assert to_sql(equality) =~ ~s[p0."name" = p0."description" COLLATE "de-x-icu"]
      assert to_sql(inequality) =~ ~s[p0."name" <> p0."description" COLLATE "de-x-icu"]
      assert to_sql(greater) =~ ~s[p0."name" >= p0."description" COLLATE "de-x-icu"]
    end
  end

  describe "case mapping" do
    # PostgreSQL takes case mapping from the collation of the argument,
    # which is what distinguishes these from the SQLite expansions.
    test "lower/1 and lower/2 collate the argument" do
      assert to_sql(from p in "products", select: lower(p.name)) =~
               ~s[lower(p0."name" COLLATE "en-x-icu")]

      assert to_sql(from p in "products", select: lower(p.name, "tr")) =~
               ~s[lower(p0."name" COLLATE "tr-x-icu")]
    end

    test "upper/1 and upper/2 collate the argument" do
      assert to_sql(from p in "products", select: upper(p.name)) =~
               ~s[upper(p0."name" COLLATE "en-x-icu")]

      assert to_sql(from p in "products", select: upper(p.name, "tr")) =~
               ~s[upper(p0."name" COLLATE "tr-x-icu")]
    end

    test "initcap/1 and initcap/2 collate the argument" do
      assert to_sql(from p in "products", select: initcap(p.name)) =~
               ~s[initcap(p0."name" COLLATE "en-x-icu")]

      assert to_sql(from p in "products", select: initcap(p.name, "nl")) =~
               ~s[initcap(p0."name" COLLATE "nl-x-icu")]
    end
  end

  describe "at_time_zone/2" do
    test "canonicalizes the zone" do
      query = from e in "events", select: at_time_zone(e.starts_at, "Australia/Sydney")

      assert to_sql(query) =~ ~s[AT TIME ZONE]
    end

    test "accepts a pinned zone" do
      zone = "Australia/Sydney"
      query = from e in "events", select: at_time_zone(e.starts_at, ^zone)

      assert to_sql(query) =~ ~s[AT TIME ZONE]
    end

    test "raises on an unknown zone when the query is built" do
      assert_raise Localize.UnknownTimezoneError, fn ->
        Localize.Ecto.Type.TimeZone.canonicalize!("Mars/Olympus_Mons")
      end
    end
  end

  describe "ts_match/2,3" do
    test "ts_match/2 uses the current locale's configuration" do
      query = from p in "products", where: ts_match(p.description, "chair"), select: p.id

      assert to_sql(query) =~ "to_tsvector"
      assert to_sql(query) =~ "websearch_to_tsquery"
    end

    test "ts_match/3 resolves the locale's configuration" do
      query = from p in "products", where: ts_match(p.description, "stuhl", "de"), select: p.id

      assert to_sql(query) =~ "to_tsvector"
    end

    test "ts_match/3 accepts a configuration name directly" do
      query =
        from p in "products",
          where: ts_match(p.description, "stuhl", config: "german"),
          select: p.id

      assert to_sql(query) =~ "to_tsvector"
    end

    # A pinned locale is deliberately not tested here: for a literal
    # binary the compiler can prove the macro's is_list/1 branch dead
    # and warns. The pin itself goes through Builder.unpin/1, which the
    # collate/2 pinned-locale test above already covers.
  end

  describe "parity with Localize.Ecto" do
    test "the compatibility module emits identical SQL" do
      via_alias =
        from p in "products", order_by: Localize.Ecto.collate(p.name, "sv"), select: p.name

      via_module = from p in "products", order_by: collate(p.name, "sv"), select: p.name

      assert to_sql(via_alias) == to_sql(via_module)
    end
  end
end

defmodule Localize.Ecto.TaggedDecimalSQLTest do
  # Creates composite types and aggregates, which are database-global.
  use ExUnit.Case, async: false

  alias Localize.Ecto.TaggedDecimal
  alias Localize.Ecto.TaggedDecimal.DDL
  alias Localize.Ecto.TestRepo

  @plain_spec TaggedDecimal.new!(
                type_name: "tagged_plain_test",
                tag_field: "tag",
                value_field: "value",
                function_prefix: "tagged_plain_test",
                tag_description: "tag"
              )

  @usage_spec TaggedDecimal.new!(
                type_name: "tagged_usage_test",
                tag_field: "tag",
                value_field: "value",
                function_prefix: "tagged_usage_test",
                tag_description: "tag",
                extra_fields: [{"usage", "varchar"}]
              )

  setup_all do
    for spec <- [@plain_spec, @usage_spec] do
      tear_down(spec)

      execute!(DDL.create_type(spec))
      execute!(DDL.define_sum_function(spec))
      execute!(DDL.define_minmax_functions(spec))
      execute!(DDL.define_avg_function(spec))

      for operator <- [:add, :subtract, :negate] do
        execute!(DDL.define_operator(spec, operator))
      end

      execute!("CREATE TABLE #{spec.type_name}_rows (id serial, amount #{spec.type_name});")
    end

    on_exit(fn -> Enum.each([@plain_spec, @usage_spec], &tear_down/1) end)

    :ok
  end

  setup do
    for spec <- [@plain_spec, @usage_spec] do
      execute!("TRUNCATE #{spec.type_name}_rows;")
    end

    :ok
  end

  describe "the generated composite type" do
    test "round trips a tag and a decimal" do
      insert(@plain_spec, "EUR", "1.25")

      assert query_one("SELECT amount::text FROM tagged_plain_test_rows") == "(EUR,1.25)"
    end

    test "exposes its fields as functions of the composite" do
      insert(@plain_spec, "EUR", "1.25")

      assert query_one("SELECT tag(amount) FROM tagged_plain_test_rows") == "EUR"
      assert query_one("SELECT value(amount)::text FROM tagged_plain_test_rows") == "1.25"
    end
  end

  describe "the generated sum aggregate" do
    test "sums rows carrying the same tag" do
      insert(@plain_spec, "EUR", "1.25")
      insert(@plain_spec, "EUR", "2.50")
      insert(@plain_spec, "EUR", "0.25")

      assert query_one("SELECT sum(amount)::text FROM tagged_plain_test_rows") == "(EUR,4.00)"
    end

    test "sums a single row" do
      insert(@plain_spec, "JPY", "100")

      assert query_one("SELECT sum(amount)::text FROM tagged_plain_test_rows") == "(JPY,100)"
    end

    test "returns null over no rows" do
      assert query_one("SELECT sum(amount)::text FROM tagged_plain_test_rows") == nil
    end

    test "ignores null values" do
      insert(@plain_spec, "EUR", "1.25")
      execute!("INSERT INTO tagged_plain_test_rows (amount) VALUES (NULL);")

      assert query_one("SELECT sum(amount)::text FROM tagged_plain_test_rows") == "(EUR,1.25)"
    end

    test "raises when the tags differ" do
      insert(@plain_spec, "EUR", "1.25")
      insert(@plain_spec, "JPY", "100")

      exception =
        assert_raise Postgrex.Error, fn ->
          query_one("SELECT sum(amount)::text FROM tagged_plain_test_rows")
        end

      # SQLSTATE 22033 is what these aggregates have always raised. It is
      # named invalid_sql_json_subscript from PostgreSQL 16 onwards, which
      # is not what the message means, but it is the code deployed
      # functions raise and consumers already match on. See the
      # `:errcode` option of `Localize.Ecto.TaggedDecimal.new/1`.
      assert exception.postgres.pg_code == "22033"
      assert exception.postgres.message =~ "Incompatible tags. Expected all tags to be"
      assert exception.postgres.hint == "Please ensure all columns have the same tag"
    end

    test "groups independently by tag" do
      insert(@plain_spec, "EUR", "1.25")
      insert(@plain_spec, "EUR", "2.75")
      insert(@plain_spec, "JPY", "100")

      rows =
        query_all(
          "SELECT sum(amount)::text FROM tagged_plain_test_rows GROUP BY tag(amount) ORDER BY tag(amount)"
        )

      assert rows == [["(EUR,4.00)"], ["(JPY,100)"]]
    end
  end

  describe "the generated combine function" do
    # PostgreSQL only calls the combine function when it actually
    # parallelises the aggregate, which a small test table will not
    # trigger, so it is called directly here. It is the reason the
    # aggregate can be declared parallel safe, and it carried an
    # undeclared variable in the SQL this generator replaces.
    test "merges two partial states" do
      combine = TaggedDecimal.function_name(@plain_spec, :sum_combine)

      assert query_one(
               "SELECT #{combine}(ROW('EUR', 1.25)::tagged_plain_test, ROW('EUR', 2.75)::tagged_plain_test)::text"
             ) == "(EUR,4.00)"
    end

    test "raises when the partial states carry different tags" do
      combine = TaggedDecimal.function_name(@plain_spec, :sum_combine)

      exception =
        assert_raise Postgrex.Error, fn ->
          query_one(
            "SELECT #{combine}(ROW('EUR', 1.25)::tagged_plain_test, ROW('JPY', 100)::tagged_plain_test)::text"
          )
        end

      assert exception.postgres.pg_code == "22033"
    end
  end

  describe "the generated min and max aggregates" do
    test "return the extreme values" do
      insert(@plain_spec, "EUR", "5.00")
      insert(@plain_spec, "EUR", "1.25")
      insert(@plain_spec, "EUR", "10.50")

      assert query_one("SELECT min(amount)::text FROM tagged_plain_test_rows") == "(EUR,1.25)"
      assert query_one("SELECT max(amount)::text FROM tagged_plain_test_rows") == "(EUR,10.50)"
    end

    # A sentinel-seeded extremum would return 0 here rather than the
    # smallest value actually present.
    test "do not treat zero as a lower bound" do
      insert(@plain_spec, "EUR", "5.00")
      insert(@plain_spec, "EUR", "10.50")

      assert query_one("SELECT min(amount)::text FROM tagged_plain_test_rows") == "(EUR,5.00)"
    end

    test "handle negative values" do
      insert(@plain_spec, "EUR", "-5.00")
      insert(@plain_spec, "EUR", "-1.25")

      assert query_one("SELECT min(amount)::text FROM tagged_plain_test_rows") == "(EUR,-5.00)"
      assert query_one("SELECT max(amount)::text FROM tagged_plain_test_rows") == "(EUR,-1.25)"
    end

    test "raise when the tags differ" do
      insert(@plain_spec, "EUR", "1.25")
      insert(@plain_spec, "JPY", "100")

      for aggregate <- ["min", "max"] do
        assert_raise Postgrex.Error, fn ->
          query_one("SELECT #{aggregate}(amount)::text FROM tagged_plain_test_rows")
        end
      end
    end

    test "combine functions merge two partial states" do
      for {extremum, expected} <- [min: "(EUR,1.25)", max: "(EUR,2.75)"] do
        combine = TaggedDecimal.function_name(@plain_spec, :"#{extremum}_combine")

        assert query_one(
                 "SELECT #{combine}(ROW('EUR', 1.25)::tagged_plain_test, ROW('EUR', 2.75)::tagged_plain_test)::text"
               ) == expected
      end
    end
  end

  describe "the generated avg aggregate" do
    test "averages rows carrying the same tag" do
      insert(@plain_spec, "EUR", "1.00")
      insert(@plain_spec, "EUR", "2.00")
      insert(@plain_spec, "EUR", "3.00")

      assert query_one("SELECT avg(amount)::text FROM tagged_plain_test_rows") ==
               "(EUR,2.0000000000000000)"
    end

    test "returns null over no rows" do
      assert query_one("SELECT avg(amount)::text FROM tagged_plain_test_rows") == nil
    end

    test "raises when the tags differ" do
      insert(@plain_spec, "EUR", "1.25")
      insert(@plain_spec, "JPY", "100")

      assert_raise Postgrex.Error, fn ->
        query_one("SELECT avg(amount)::text FROM tagged_plain_test_rows")
      end
    end

    test "combine function merges two partial states" do
      combine = TaggedDecimal.function_name(@plain_spec, :avg_combine)
      state_type = TaggedDecimal.function_name(@plain_spec, :avg_state_type)

      assert query_one(
               "SELECT #{combine}(ROW('EUR', 3.0, 2)::#{state_type}, ROW('EUR', 3.0, 1)::#{state_type})::text"
             ) == "(EUR,6.0,3)"
    end

    test "groups independently by tag" do
      insert(@plain_spec, "EUR", "1.00")
      insert(@plain_spec, "EUR", "3.00")
      insert(@plain_spec, "JPY", "100")

      rows =
        query_all(
          "SELECT tag(avg(amount)), value(avg(amount))::text FROM tagged_plain_test_rows GROUP BY tag(amount) ORDER BY tag(amount)"
        )

      assert rows == [["EUR", "2.0000000000000000"], ["JPY", "100.0000000000000000"]]
    end
  end

  describe "the generated operators" do
    test "add two values carrying the same tag" do
      assert query_one(
               "SELECT (ROW('EUR', 1.25)::tagged_plain_test + ROW('EUR', 2.75)::tagged_plain_test)::text"
             ) == "(EUR,4.00)"
    end

    test "subtract two values carrying the same tag" do
      assert query_one(
               "SELECT (ROW('EUR', 5.00)::tagged_plain_test - ROW('EUR', 2.75)::tagged_plain_test)::text"
             ) == "(EUR,2.25)"
    end

    test "negate a value" do
      assert query_one("SELECT (- ROW('EUR', 1.25)::tagged_plain_test)::text") == "(EUR,-1.25)"
    end

    test "raise when the tags differ" do
      for operator <- ["+", "-"] do
        exception =
          assert_raise Postgrex.Error, fn ->
            query_one(
              "SELECT (ROW('EUR', 1.25)::tagged_plain_test #{operator} ROW('JPY', 100)::tagged_plain_test)::text"
            )
          end

        assert exception.postgres.message =~
                 "Incompatible tags for #{operator} operator. Expected both tags to be"

        assert exception.postgres.hint == "Please ensure both columns have the same tag"
      end
    end
  end

  describe "extra fields" do
    test "are carried through the aggregation" do
      execute!(
        "INSERT INTO tagged_usage_test_rows (amount) VALUES (ROW('metre', 1.5, 'road')::tagged_usage_test);"
      )

      execute!(
        "INSERT INTO tagged_usage_test_rows (amount) VALUES (ROW('metre', 2.5, 'road')::tagged_usage_test);"
      )

      assert query_one("SELECT sum(amount)::text FROM tagged_usage_test_rows") ==
               "(metre,4.0,road)"
    end

    test "still raise on a tag mismatch" do
      execute!(
        "INSERT INTO tagged_usage_test_rows (amount) VALUES (ROW('metre', 1.5, 'road')::tagged_usage_test);"
      )

      execute!(
        "INSERT INTO tagged_usage_test_rows (amount) VALUES (ROW('foot', 2.5, 'road')::tagged_usage_test);"
      )

      assert_raise Postgrex.Error, fn ->
        query_one("SELECT sum(amount)::text FROM tagged_usage_test_rows")
      end
    end
  end

  # A previous aborted run may have left any of these behind, and
  # CREATE OPERATOR has no OR REPLACE form, so everything is removed
  # before being installed.
  defp tear_down(spec) do
    quietly("DROP TABLE IF EXISTS #{spec.type_name}_rows;")

    for operator <- [:add, :subtract, :negate] do
      quietly(DDL.drop_operator(spec, operator))
    end

    quietly(DDL.drop_avg_function(spec))
    quietly(DDL.drop_minmax_functions(spec))
    quietly(DDL.drop_sum_function(spec))
    quietly("DROP TYPE IF EXISTS #{spec.type_name} CASCADE;")
  end

  defp insert(spec, tag, value) do
    execute!(
      "INSERT INTO #{spec.type_name}_rows (amount) VALUES (ROW('#{tag}', #{value})::#{spec.type_name});"
    )
  end

  # The generating functions return several statements separated by two
  # blank lines; the extended query protocol takes one at a time.
  defp execute!(sql) do
    sql
    |> String.split("\n\n\n")
    |> Enum.each(&TestRepo.query!/1)
  end

  defp quietly(sql) do
    sql
    |> String.split("\n\n\n")
    |> Enum.each(&TestRepo.query(&1))
  end

  defp query_one(sql) do
    [[value]] = TestRepo.query!(sql).rows
    value
  end

  defp query_all(sql) do
    TestRepo.query!(sql).rows
  end
end

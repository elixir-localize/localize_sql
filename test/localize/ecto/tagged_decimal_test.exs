defmodule Localize.Ecto.TaggedDecimalTest do
  use ExUnit.Case, async: true

  alias Localize.Ecto.TaggedDecimal
  alias Localize.Ecto.TaggedDecimal.DDL

  doctest Localize.Ecto.TaggedDecimal
  doctest Localize.Ecto.TaggedDecimal.DDL

  # The specifications of the two domains that must keep working. Their
  # composite types, field names and function names exist in deployed
  # databases, so the generator has to reproduce them exactly — an
  # aggregate names the functions it is built from, and a DROP names the
  # function it removes.
  defp money_spec do
    TaggedDecimal.new!(
      type_name: "money_with_currency",
      tag_field: "currency_code",
      value_field: "amount",
      function_prefix: "money",
      tag_description: "currency code"
    )
  end

  defp unit_spec do
    TaggedDecimal.new!(
      type_name: "cldr_unit",
      tag_field: "unit",
      value_field: "value",
      function_prefix: "unit",
      argument_name: "unit",
      tag_description: "unit name",
      function_names: %{sum_state: "unit_state_function"}
    )
  end

  defp unit_with_usage_spec do
    TaggedDecimal.new!(
      type_name: "cldr_unit_with_usage",
      tag_field: "unit",
      value_field: "value",
      function_prefix: "unit_with_usage",
      argument_name: "unit",
      tag_description: "unit name",
      extra_fields: [{"usage", "varchar"}],
      function_names: %{sum_state: "unit_with_usage_state_function"}
    )
  end

  describe "specifications" do
    test "require the identifying options" do
      assert {:error, %ArgumentError{} = exception} = TaggedDecimal.new(type_name: "cldr_unit")
      assert Exception.message(exception) =~ ":tag_field"
      assert Exception.message(exception) =~ ":value_field"
    end

    test "reject extra fields that are not {name, sql_type} tuples" do
      assert {:error, %ArgumentError{}} =
               TaggedDecimal.new(
                 type_name: "cldr_unit",
                 tag_field: "unit",
                 value_field: "value",
                 function_prefix: "unit",
                 tag_description: "unit name",
                 extra_fields: [:usage]
               )
    end

    test "derive the mismatch message and hint from the tag description" do
      assert money_spec().mismatch_message ==
               "Incompatible currency codes. Expected all currency codes to be %"

      assert money_spec().mismatch_hint ==
               "Please ensure all columns have the same currency code"
    end

    test "default the plpgsql argument name to the function prefix" do
      assert money_spec().argument_name == "money"
    end

    test "escape single quotes in message literals" do
      spec =
        TaggedDecimal.new!(
          type_name: "t",
          tag_field: "tag",
          value_field: "value",
          function_prefix: "t",
          tag_description: "tag",
          mismatch_message: "Don't mix tags: %"
        )

      assert DDL.define_sum_function(spec) =~ "'Don''t mix tags: %'"
    end
  end

  describe "generated identifiers match the deployed contract" do
    test "money composite type" do
      assert DDL.create_type(money_spec()) ==
               "CREATE TYPE public.money_with_currency AS (currency_code varchar, amount numeric);"
    end

    test "unit composite types" do
      assert DDL.create_type(unit_spec()) ==
               "CREATE TYPE public.cldr_unit AS (unit varchar, value numeric);"

      assert DDL.create_type(unit_with_usage_spec()) ==
               "CREATE TYPE public.cldr_unit_with_usage AS (unit varchar, value numeric, usage varchar);"
    end

    test "money sum function signatures and aggregate" do
      sql = DDL.define_sum_function(money_spec())

      assert sql =~
               "CREATE OR REPLACE FUNCTION money_sum_state_function(agg_state money_with_currency, money money_with_currency)"

      assert sql =~
               "CREATE OR REPLACE FUNCTION money_sum_combine_function(agg_state1 money_with_currency, agg_state2 money_with_currency)"

      assert sql =~ "CREATE OR REPLACE AGGREGATE sum(money_with_currency)"
      assert sql =~ "sfunc = money_sum_state_function"
      assert sql =~ "combinefunc = money_sum_combine_function"
      assert sql =~ "parallel = SAFE"
    end

    test "unit sum function keeps its historical name" do
      sql = DDL.define_sum_function(unit_spec())

      assert sql =~
               "CREATE OR REPLACE FUNCTION unit_state_function(agg_state cldr_unit, unit cldr_unit)"

      assert sql =~ "sfunc = unit_state_function"
    end

    test "unit with usage sum function keeps its historical name" do
      sql = DDL.define_sum_function(unit_with_usage_spec())

      assert sql =~
               "CREATE OR REPLACE FUNCTION unit_with_usage_state_function(agg_state cldr_unit_with_usage, unit cldr_unit_with_usage)"
    end

    test "drops name the functions that were created" do
      sql = DDL.drop_sum_function(unit_with_usage_spec())

      assert sql =~ "DROP AGGREGATE IF EXISTS sum(cldr_unit_with_usage);"

      assert sql =~
               "DROP FUNCTION IF EXISTS unit_with_usage_state_function(cldr_unit_with_usage, cldr_unit_with_usage);"
    end
  end

  describe "extra fields" do
    test "are declared, carried and returned by the state function" do
      sql = DDL.define_sum_function(unit_with_usage_spec())

      assert sql =~ "usage varchar;"
      assert sql =~ "usage := usage(unit);"
      assert sql =~ "RETURN row(expected_tag, addition, usage);"
    end

    test "are absent when the specification has none" do
      refute DDL.define_sum_function(unit_spec()) =~ "usage"
    end
  end

  describe "migration wrapping" do
    test "a single-line statement is wrapped in execute/1" do
      assert DDL.execute("DROP TYPE public.cldr_unit;") ==
               ~s|execute "DROP TYPE public.cldr_unit;"|
    end

    test "a multi-line statement is wrapped in a heredoc" do
      wrapped = DDL.execute("CREATE THING\n  BODY;")

      assert wrapped == "execute \"\"\"\nCREATE THING\n  BODY;\n\"\"\""
    end

    test "execute_each emits one execute per statement" do
      wrapped = DDL.execute_each(DDL.drop_sum_function(unit_spec()))

      assert length(String.split(wrapped, "\n")) == 3
    end

    test "an append is added to each statement" do
      wrapped =
        DDL.execute_each(DDL.drop_sum_function(unit_spec()), "|> adjust_for_type(repo())")

      assert wrapped =~
               "execute \"DROP AGGREGATE IF EXISTS sum(cldr_unit);\" |> adjust_for_type(repo())"
    end
  end
end

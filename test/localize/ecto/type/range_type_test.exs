defmodule Localize.Ecto.Type.RangeTypeTest do
  use ExUnit.Case, async: false

  alias Localize.Ecto.TestRepo
  alias Localize.Ecto.Type.DateRange
  alias Localize.Ecto.Type.IntegerRange

  setup_all do
    TestRepo.query!(
      "CREATE TABLE IF NOT EXISTS range_rows (id serial, ints int8range, dates daterange)"
    )

    on_exit(fn -> TestRepo.query("DROP TABLE IF EXISTS range_rows") end)
    :ok
  end

  setup do
    TestRepo.query!("TRUNCATE range_rows")
    :ok
  end

  describe "IntegerRange cast/1" do
    test "accepts an ascending unit-step range" do
      assert IntegerRange.cast(1..10) == {:ok, 1..10}
    end

    test "accepts a single-element range" do
      assert IntegerRange.cast(5..5) == {:ok, 5..5}
    end

    test "rejects a stepped range" do
      assert IntegerRange.cast(1..10//2) ==
               {:error,
                message: "is not an ascending integer range with a step of 1", value: 1..10//2}
    end

    test "rejects a descending (empty) range" do
      assert {:error, message: _message, value: 10..1//1} = IntegerRange.cast(10..1//1)
    end

    test "casts nil and refuses non-ranges" do
      assert IntegerRange.cast(nil) == {:ok, nil}
      assert IntegerRange.cast("1..10") == :error
    end
  end

  describe "IntegerRange dump/1" do
    test "dumps to an inclusive Postgrex range" do
      assert {:ok,
              %Postgrex.Range{lower: 1, upper: 10, lower_inclusive: true, upper_inclusive: true}} =
               IntegerRange.dump(1..10)
    end

    test "refuses a stepped range" do
      assert IntegerRange.dump(1..10//2) == :error
    end
  end

  describe "IntegerRange load/1 normalizes PostgreSQL's canonical form" do
    test "a half-open [lower, upper) range loads inclusive" do
      canonical = %Postgrex.Range{
        lower: 1,
        upper: 11,
        lower_inclusive: true,
        upper_inclusive: false
      }

      assert IntegerRange.load(canonical) == {:ok, 1..10}
    end

    test "an unbounded range has no equivalent" do
      assert IntegerRange.load(%Postgrex.Range{
               lower: nil,
               upper: 10,
               lower_inclusive: false,
               upper_inclusive: false
             }) == :error
    end
  end

  describe "IntegerRange round trip through PostgreSQL" do
    test "an integer range survives store and load" do
      {:ok, dumped} = IntegerRange.dump(1..10)
      TestRepo.query!("INSERT INTO range_rows (ints) VALUES ($1)", [dumped])

      %{rows: [[stored]]} = TestRepo.query!("SELECT ints FROM range_rows")

      assert IntegerRange.load(stored) == {:ok, 1..10}
    end

    test "the range contains what it should in the database" do
      {:ok, dumped} = IntegerRange.dump(1..10)
      TestRepo.query!("INSERT INTO range_rows (ints) VALUES ($1)", [dumped])

      assert %{rows: [[true]]} = TestRepo.query!("SELECT ints @> 10::int8 FROM range_rows")
      assert %{rows: [[false]]} = TestRepo.query!("SELECT ints @> 11::int8 FROM range_rows")
    end
  end

  describe "DateRange cast/1" do
    test "accepts an ascending range" do
      range = Date.range(~D[2024-01-01], ~D[2024-12-31])
      assert DateRange.cast(range) == {:ok, range}
    end

    test "rejects a descending range" do
      range = Date.range(~D[2024-12-31], ~D[2024-01-01], -1)

      assert DateRange.cast(range) ==
               {:error,
                message: "is not an ascending date range with a step of one day", value: range}
    end

    test "casts nil and refuses non-ranges" do
      assert DateRange.cast(nil) == {:ok, nil}
      assert DateRange.cast(~D[2024-01-01]) == :error
    end
  end

  describe "DateRange load/1 normalizes PostgreSQL's canonical form" do
    test "a half-open [lower, upper) range loads inclusive" do
      canonical = %Postgrex.Range{
        lower: ~D[2024-01-01],
        upper: ~D[2025-01-01],
        lower_inclusive: true,
        upper_inclusive: false
      }

      assert DateRange.load(canonical) == {:ok, Date.range(~D[2024-01-01], ~D[2024-12-31])}
    end
  end

  describe "DateRange round trip through PostgreSQL" do
    test "a date range survives store and load" do
      range = Date.range(~D[2024-01-01], ~D[2024-12-31])
      {:ok, dumped} = DateRange.dump(range)
      TestRepo.query!("INSERT INTO range_rows (dates) VALUES ($1)", [dumped])

      %{rows: [[stored]]} = TestRepo.query!("SELECT dates FROM range_rows")

      assert DateRange.load(stored) == {:ok, range}
    end
  end
end

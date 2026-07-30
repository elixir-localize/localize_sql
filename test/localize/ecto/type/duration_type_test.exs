defmodule Localize.Ecto.Type.DurationTypeTest do
  use ExUnit.Case, async: false

  alias Localize.Duration.Ecto.Type, as: LocalizeDuration
  alias Localize.Ecto.TestRepo
  alias Localize.Ecto.Type.Duration, as: ElixirDuration

  setup_all do
    TestRepo.query!("CREATE TABLE IF NOT EXISTS duration_rows (id serial, span interval)")
    on_exit(fn -> TestRepo.query("DROP TABLE IF EXISTS duration_rows") end)
    :ok
  end

  setup do
    TestRepo.query!("TRUNCATE duration_rows")
    :ok
  end

  describe "Localize.Duration" do
    test "stores as interval" do
      assert LocalizeDuration.type() == :interval
    end

    test "dumps calendar units into interval components" do
      duration = %Localize.Duration{year: 1, month: 2, day: 3, hour: 4, minute: 5, second: 6}

      assert {:ok, %Postgrex.Interval{months: 14, days: 3, secs: 14_706, microsecs: 0}} =
               LocalizeDuration.dump(duration)
    end

    test "round trips through PostgreSQL" do
      duration = %Localize.Duration{
        year: 1,
        month: 2,
        day: 3,
        hour: 4,
        minute: 5,
        second: 6,
        microsecond: {7, 6}
      }

      {:ok, dumped} = LocalizeDuration.dump(duration)
      TestRepo.query!("INSERT INTO duration_rows (span) VALUES ($1)", [dumped])
      %{rows: [[stored]]} = TestRepo.query!("SELECT span FROM duration_rows")

      assert LocalizeDuration.load(stored) == {:ok, duration}
    end

    test "normalizes interchangeable units on load" do
      # Ninety minutes has no distinct interval representation; it is the
      # same interval as one hour and thirty minutes.
      {:ok, dumped} = LocalizeDuration.dump(%Localize.Duration{minute: 90})

      assert {:ok, %Localize.Duration{hour: 1, minute: 30, second: 0}} =
               LocalizeDuration.load(dumped)
    end

    test "casts nil and a struct, refuses others" do
      duration = %Localize.Duration{hour: 1}
      assert LocalizeDuration.cast(duration) == {:ok, duration}
      assert LocalizeDuration.cast(nil) == {:ok, nil}
      assert LocalizeDuration.cast(3600) == :error
    end
  end

  describe "Elixir Duration" do
    test "stores as interval" do
      assert ElixirDuration.type() == :interval
    end

    test "folds weeks into days on dump" do
      assert {:ok, %Postgrex.Interval{days: 17}} =
               ElixirDuration.dump(Duration.new!(week: 2, day: 3))
    end

    test "round trips through PostgreSQL" do
      duration = Duration.new!(year: 1, month: 2, day: 3, hour: 4, minute: 5, second: 6)

      {:ok, dumped} = ElixirDuration.dump(duration)
      TestRepo.query!("INSERT INTO duration_rows (span) VALUES ($1)", [dumped])
      %{rows: [[stored]]} = TestRepo.query!("SELECT span FROM duration_rows")

      assert ElixirDuration.load(stored) == {:ok, duration}
    end

    test "a week loads back as seven days" do
      {:ok, dumped} = ElixirDuration.dump(Duration.new!(week: 1))

      assert {:ok, loaded} = ElixirDuration.load(dumped)
      assert loaded == Duration.new!(day: 7)
    end

    test "casts nil and a duration, refuses others" do
      duration = Duration.new!(hour: 1)
      assert ElixirDuration.cast(duration) == {:ok, duration}
      assert ElixirDuration.cast(nil) == {:ok, nil}
      assert ElixirDuration.cast(3600) == :error
    end
  end
end

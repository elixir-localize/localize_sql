defmodule Localize.Ecto.TypeEdgeCaseTest do
  use ExUnit.Case, async: true

  alias Localize.Currency.Ecto.Type, as: Currency
  alias Localize.Duration.Ecto.Type, as: LocalizeDuration
  alias Localize.Ecto.Type.DateRange
  alias Localize.Ecto.Type.Duration, as: ElixirDuration
  alias Localize.Ecto.Type.IntegerRange
  alias Localize.LanguageTag.Ecto.Type, as: LanguageTag
  alias Localize.Script.Ecto.Type, as: Script
  alias Localize.Territory.Ecto.Type, as: Territory

  # Every type must treat nil as nil in all three directions, and refuse
  # a value of the wrong shape rather than raising.
  describe "nil handling" do
    test "casts, loads and dumps nil" do
      for type <- [Currency, Territory, Script, LanguageTag, LocalizeDuration, ElixirDuration] do
        assert type.cast(nil) == {:ok, nil}, "#{inspect(type)} cast"
        assert type.load(nil) == {:ok, nil}, "#{inspect(type)} load"
        assert type.dump(nil) == {:ok, nil}, "#{inspect(type)} dump"
      end
    end

    test "range types treat nil as nil" do
      for type <- [IntegerRange, DateRange] do
        assert type.cast(nil) == {:ok, nil}, "#{inspect(type)} cast"
        assert type.load(nil) == {:ok, nil}, "#{inspect(type)} load"
        assert type.dump(nil) == {:ok, nil}, "#{inspect(type)} dump"
      end
    end
  end

  describe "wrong-shaped values are refused, not raised" do
    test "code types refuse non-codes" do
      for type <- [Currency, Territory, Script] do
        assert type.cast(1.5) == :error, "#{inspect(type)} cast"
        assert type.load(42) == :error, "#{inspect(type)} load"
        assert type.dump(1.5) == :error, "#{inspect(type)} dump"
      end
    end

    test "language tag refuses a non-identifier" do
      assert LanguageTag.cast(42) == :error
      assert LanguageTag.load(42) == :error
      assert LanguageTag.dump(42) == :error
    end

    test "duration types refuse non-durations" do
      for type <- [LocalizeDuration, ElixirDuration] do
        assert type.cast(3600) == :error, "#{inspect(type)} cast"
        assert type.load(3600) == :error, "#{inspect(type)} load"
        assert type.dump(3600) == :error, "#{inspect(type)} dump"
      end
    end

    test "range types refuse non-ranges" do
      for type <- [IntegerRange, DateRange] do
        assert type.load("not a range") == :error, "#{inspect(type)} load"
        assert type.dump("not a range") == :error, "#{inspect(type)} dump"
      end
    end
  end

  describe "code types accept every documented input form" do
    test "currency accepts atom, string and struct" do
      assert Currency.cast(:USD) == {:ok, :USD}
      assert Currency.cast("usd") == {:ok, :USD}
      assert Currency.cast(%Localize.Currency{code: :EUR}) == {:ok, :EUR}
      assert Currency.dump(%Localize.Currency{code: :EUR}) == {:ok, "EUR"}
    end

    test "territory accepts atom and string" do
      assert Territory.cast(:GB) == {:ok, :GB}
      assert Territory.dump("gb") == {:ok, "GB"}
    end

    test "script accepts atom and string" do
      assert Script.cast(:Latn) == {:ok, :Latn}
      assert Script.dump("cyrl") == {:ok, "Cyrl"}
    end

    test "unknown codes are refused on dump as well as cast" do
      assert Currency.dump(:ZZZ) == :error
      assert Territory.dump(:ZZZZ) == :error
      assert Script.dump(:Xyzq) == :error
    end
  end

  describe "language tag" do
    test "dumps a locale given as a string or atom" do
      assert LanguageTag.dump("en-US") == {:ok, "en-US"}
      assert LanguageTag.dump(:"en-US") == {:ok, "en-US"}
    end

    test "dumping an invalid identifier fails" do
      assert LanguageTag.dump("this-is-not-a-locale") == :error
    end

    test "a tag passes through cast unchanged" do
      {:ok, tag} = Localize.validate_locale("de-DE")
      assert LanguageTag.cast(tag) == {:ok, tag}
    end
  end

  describe "durations" do
    test "an empty duration round trips" do
      {:ok, dumped} = LocalizeDuration.dump(%Localize.Duration{})
      assert {:ok, %Localize.Duration{}} = LocalizeDuration.load(dumped)
    end

    test "an Elixir duration with only microseconds round trips" do
      duration = Duration.new!(microsecond: {500, 6})
      {:ok, dumped} = ElixirDuration.dump(duration)
      {:ok, loaded} = ElixirDuration.load(dumped)

      assert loaded.microsecond == {500, 6}
    end

    test "both report interval as their database type" do
      assert LocalizeDuration.type() == :interval
      assert ElixirDuration.type() == :interval
    end
  end

  describe "ranges" do
    test "report their database types" do
      assert IntegerRange.type() == :int8range
      assert DateRange.type() == :daterange
    end

    test "an integer range round trips through its dumped form" do
      {:ok, dumped} = IntegerRange.dump(1..10)
      assert IntegerRange.load(dumped) == {:ok, 1..10}
    end

    test "a date range round trips through its dumped form" do
      range = Date.range(~D[2024-01-01], ~D[2024-01-31])
      {:ok, dumped} = DateRange.dump(range)
      assert DateRange.load(dumped) == {:ok, range}
    end

    test "an unbounded date range has no Elixir equivalent" do
      assert DateRange.load(%Postgrex.Range{
               lower: nil,
               upper: ~D[2024-12-31],
               lower_inclusive: false,
               upper_inclusive: true
             }) == :error
    end

    test "a descending date range is refused on dump" do
      assert DateRange.dump(Date.range(~D[2024-12-31], ~D[2024-01-01], -1)) == :error
    end
  end
end

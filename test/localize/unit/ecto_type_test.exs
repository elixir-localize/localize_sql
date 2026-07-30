defmodule Localize.Unit.Ecto.TypeTest do
  use ExUnit.Case, async: true

  alias Localize.Unit.Ecto.Composite.Type, as: Composite
  alias Localize.Unit.Ecto.Map.Type, as: Map
  alias Localize.UnitWithUsage.Ecto.Composite.Type, as: UsageComposite

  defp meter(value, options \\ []) do
    {:ok, unit} = Localize.Unit.new(Decimal.new(value), "meter", options)
    unit
  end

  describe "composite type" do
    test "reports the cldr_unit database type" do
      assert Composite.type() == :cldr_unit
    end

    test "loads a tuple into a unit" do
      assert {:ok, unit} = Composite.load({"meter", Decimal.new("2.5")})
      assert unit.name == "meter"
      assert Decimal.equal?(unit.value, Decimal.new("2.5"))
    end

    test "dumps a unit into a tuple" do
      assert {:ok, {"meter", value}} = Composite.dump(meter("2.5"))
      assert Decimal.equal?(value, Decimal.new("2.5"))
    end

    test "casts a string-keyed map" do
      assert {:ok, unit} = Composite.cast(%{"unit" => "meter", "value" => "2.5"})
      assert unit.name == "meter"
    end

    test "casts an empty value to nil" do
      assert Composite.cast(%{"unit" => "meter", "value" => ""}) == {:ok, nil}
    end

    test "round trips through dump and load" do
      {:ok, dumped} = Composite.dump(meter("2.5"))
      {:ok, loaded} = Composite.load(dumped)

      assert Composite.equal?(loaded, meter("2.5"))
    end

    test "different values are not equal" do
      refute Composite.equal?(meter("2.5"), meter("3.5"))
    end
  end

  describe "map type" do
    test "reports the map database type" do
      assert Map.type() == :map
    end

    test "dumps the value as a string to preserve precision" do
      assert {:ok, %{"unit" => "meter", "value" => "2.5"}} = Map.dump(meter("2.5"))
    end

    test "round trips through dump and load" do
      {:ok, dumped} = Map.dump(meter("2.5"))
      {:ok, loaded} = Map.load(dumped)

      assert Map.equal?(loaded, meter("2.5"))
    end
  end

  describe "with-usage composite type" do
    test "reports the cldr_unit_with_usage database type" do
      assert UsageComposite.type() == :cldr_unit_with_usage
    end

    test "preserves usage across a dump and load round trip" do
      with_usage = meter("2.5", usage: "road")

      {:ok, dumped} = UsageComposite.dump(with_usage)
      assert {"meter", _value, "road"} = dumped

      {:ok, loaded} = UsageComposite.load(dumped)
      assert loaded.usage == "road"
    end

    test "loads a tuple with no usage" do
      assert {:ok, unit} = UsageComposite.load({"meter", Decimal.new("2.5"), nil})
      assert unit.name == "meter"
    end
  end
end

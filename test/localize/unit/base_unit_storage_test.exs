defmodule Localize.Unit.Ecto.BaseUnitStorageTest do
  # The unit types store a value in the base unit of its dimension, so a
  # comparison or an index on the stored value needs no unit conversion.
  use ExUnit.Case, async: true

  alias Localize.Unit.Ecto.Composite.Type, as: Composite
  alias Localize.Unit.Ecto.Map.Type, as: Map
  alias Localize.UnitWithUsage.Ecto.Composite.Type, as: UsageComposite
  alias Localize.UnitWithUsage.Ecto.Map.Type, as: UsageMap

  # {value, unit, base unit, base value}
  @conversions [
    {"2", "kilometer", "meter", "2000"},
    {"1", "foot", "meter", "0.3048"},
    {"1", "mile", "meter", "1609.344"},
    {"100", "celsius", "kelvin", "373.15"},
    {"60", "mile-per-hour", "meter-per-second", "26.8224"},
    {"1.5", "kilowatt-hour", "kilogram-square-meter-per-square-second", "5400000"},
    {"2.5", "meter", "meter", "2.5"}
  ]

  defp unit(value, name, options \\ []) do
    {:ok, unit} = Localize.Unit.new(value, name, options)
    unit
  end

  describe "the composite type dumps in the base unit" do
    for {value, name, base_name, base_value} <- @conversions do
      @value value
      @name name
      @base_name base_name
      @base_value base_value

      test "#{@value} #{@name} as #{@base_value} #{@base_name}" do
        assert {:ok, {@base_name, value}} = Composite.dump(unit(Decimal.new(@value), @name))
        assert Decimal.equal?(value, Decimal.new(@base_value))
      end
    end
  end

  describe "the map type dumps in the base unit" do
    test "2 kilometer as 2000 meter, with the value written in full" do
      assert Map.dump(unit(Decimal.new("2"), "kilometer")) ==
               {:ok, %{"unit" => "meter", "value" => "2000"}}
    end
  end

  describe "the with-usage types dump in the base unit and keep the usage" do
    test "the composite type" do
      road = unit(Decimal.new("5"), "kilometer", usage: "road")

      assert {:ok, {"meter", value, "road"}} = UsageComposite.dump(road)
      assert Decimal.equal?(value, Decimal.new("5000"))
    end

    test "the map type" do
      road = unit(Decimal.new("5"), "kilometer", usage: "road")

      assert UsageMap.dump(road) ==
               {:ok, %{"unit" => "meter", "value" => "5000", "usage" => "road"}}
    end

    test "a stored base unit loads with its usage" do
      assert {:ok, loaded} = UsageComposite.load({"meter", Decimal.new("5000"), "road"})
      assert loaded.name == "meter"
      assert loaded.usage == "road"
    end
  end

  describe "an integer value" do
    test "is stored as an exact decimal, not a float" do
      assert {:ok, {"cubic-meter", value}} = Composite.dump(unit(3, "liter"))
      assert %Decimal{} = value
      assert Decimal.equal?(value, Decimal.new("0.003"))
    end
  end

  describe "a cast value" do
    test "keeps the unit it was given until it is dumped" do
      assert {:ok, cast} = Composite.cast(%{"unit" => "kilometer", "value" => "2"})
      assert cast.name == "kilometer"
    end

    test "equals its base unit form, so a changeset records no change" do
      assert Composite.equal?(
               unit(Decimal.new("2"), "kilometer"),
               unit(Decimal.new("2000"), "meter")
             )
    end
  end
end

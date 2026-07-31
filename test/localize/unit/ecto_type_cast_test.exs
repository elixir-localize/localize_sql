defmodule Localize.Unit.Ecto.TypeCastTest do
  use ExUnit.Case, async: true

  alias Localize.Unit.Ecto.Composite.Type, as: Composite
  alias Localize.Unit.Ecto.Map.Type, as: Map
  alias Localize.UnitWithUsage.Ecto.Composite.Type, as: UsageComposite
  alias Localize.UnitWithUsage.Ecto.Map.Type, as: UsageMap

  defp meter(value, options \\ []) do
    {:ok, unit} = Localize.Unit.new(Decimal.new(value), "meter", options)
    unit
  end

  describe "composite type cast/1 accepts each value shape" do
    test "a numeric value" do
      assert {:ok, unit} = Composite.cast(%{"unit" => "meter", "value" => 25})
      assert Decimal.equal?(unit.value, Decimal.new(25))
    end

    test "a decimal value" do
      assert {:ok, unit} = Composite.cast(%{"unit" => "meter", "value" => Decimal.new("2.5")})
      assert Decimal.equal?(unit.value, Decimal.new("2.5"))
    end

    test "an atom-keyed map" do
      assert {:ok, unit} = Composite.cast(%{unit: "meter", value: "2.5"})
      assert unit.name == "meter"
    end

    test "an atom unit name" do
      assert {:ok, unit} = Composite.cast(%{"unit" => :meter, "value" => "2.5"})
      assert unit.name == "meter"
    end

    test "a unit struct passes through" do
      unit = meter("2.5")
      assert Composite.cast(unit) == {:ok, unit}
    end
  end

  describe "composite type cast/1 rejects bad input" do
    test "an unknown unit name" do
      assert {:error, message: message} = Composite.cast(%{"unit" => "sausages", "value" => "1"})
      assert is_binary(message)
    end

    test "an unparseable value" do
      assert {:error, message: message} = Composite.cast(%{"unit" => "meter", "value" => "abc"})
      assert is_binary(message)
    end

    test "a value that is not a map or unit" do
      assert Composite.cast("2.5 meters") == :error
      assert Composite.cast(42) == :error
    end
  end

  describe "composite type load and dump edge cases" do
    test "loading an unknown unit name fails" do
      assert Composite.load({"sausages", Decimal.new("1")}) == :error
    end

    test "dumping a non-unit fails" do
      assert Composite.dump(%{unit: "meter"}) == :error
    end

    test "embeds as itself" do
      assert Composite.embed_as(:json) == :self
    end

    test "non-unit equality falls back to term comparison" do
      assert Composite.equal?(nil, nil)
      refute Composite.equal?(nil, meter("1"))
    end
  end

  describe "map type load accepts each stored shape" do
    test "an integer value" do
      assert {:ok, unit} = Map.load(%{"unit" => "meter", "value" => 25})
      assert Decimal.equal?(unit.value, Decimal.new(25))
    end

    test "a string value" do
      assert {:ok, unit} = Map.load(%{"unit" => "meter", "value" => "2.5"})
      assert Decimal.equal?(unit.value, Decimal.new("2.5"))
    end

    test "a stored usage is honoured" do
      assert {:ok, unit} = Map.load(%{"unit" => "meter", "value" => "2.5", "usage" => "road"})
      assert unit.usage == "road"
    end

    test "an unparseable stored value fails" do
      assert Map.load(%{"unit" => "meter", "value" => "abc"}) == :error
    end

    test "dumping a non-unit fails" do
      assert Map.dump("2.5") == :error
    end

    test "cast is delegated to the composite type" do
      assert {:ok, unit} = Map.cast(%{"unit" => "meter", "value" => "2.5"})
      assert unit.name == "meter"
    end
  end

  describe "with-usage composite type" do
    test "casts each value shape with a usage" do
      for value <- [25, "2.5", Decimal.new("2.5")] do
        assert {:ok, unit} =
                 UsageComposite.cast(%{"unit" => "meter", "value" => value, "usage" => "road"})

        assert unit.usage == "road"
      end
    end

    test "an empty usage becomes nil" do
      assert {:ok, unit} =
               UsageComposite.cast(%{"unit" => "meter", "value" => "2.5", "usage" => ""})

      assert unit.usage == nil
    end

    test "casts an atom-keyed map carrying usage" do
      assert {:ok, unit} = UsageComposite.cast(%{unit: "meter", value: "2.5", usage: "road"})
      assert unit.usage == "road"
    end

    test "casts an empty value to nil" do
      assert UsageComposite.cast(%{"unit" => "meter", "value" => ""}) == {:ok, nil}
    end

    test "rejects an unknown unit and a non-map" do
      assert {:error, message: _} =
               UsageComposite.cast(%{"unit" => "sausages", "value" => "1", "usage" => "road"})

      assert UsageComposite.cast(42) == :error
    end

    test "dumps a nil usage as nil" do
      assert {:ok, {"meter", _value, nil}} = UsageComposite.dump(meter("2.5"))
    end

    test "dumping a non-unit fails" do
      assert UsageComposite.dump(%{}) == :error
    end

    test "loading an unknown unit fails" do
      assert UsageComposite.load({"sausages", Decimal.new("1"), "road"}) == :error
    end

    test "embeds as itself and compares equal units" do
      assert UsageComposite.embed_as(:json) == :self
      assert UsageComposite.equal?(meter("2.5"), meter("2.5"))
    end
  end

  describe "with-usage map type" do
    test "reports the map database type" do
      assert UsageMap.type() == :map
    end

    test "dumps all three parts" do
      assert {:ok, %{"unit" => "meter", "value" => "2.5", "usage" => "road"}} =
               UsageMap.dump(meter("2.5", usage: "road"))
    end

    test "dumps a nil usage" do
      assert {:ok, %{"usage" => nil}} = UsageMap.dump(meter("2.5"))
    end

    test "loads a string value with usage" do
      assert {:ok, unit} =
               UsageMap.load(%{"unit" => "meter", "value" => "2.5", "usage" => "road"})

      assert unit.usage == "road"
    end

    test "loads an integer value with usage" do
      assert {:ok, unit} = UsageMap.load(%{"unit" => "meter", "value" => 25, "usage" => "road"})
      assert Decimal.equal?(unit.value, Decimal.new(25))
    end

    test "loads an empty usage as no usage" do
      assert {:ok, unit} = UsageMap.load(%{"unit" => "meter", "value" => "2.5", "usage" => ""})
      assert unit.usage == nil
    end

    test "loads without a usage key" do
      assert {:ok, unit} = UsageMap.load(%{"unit" => "meter", "value" => "2.5"})
      assert unit.name == "meter"
    end

    test "loads an integer value without a usage key" do
      assert {:ok, unit} = UsageMap.load(%{"unit" => "meter", "value" => 25})
      assert Decimal.equal?(unit.value, Decimal.new(25))
    end

    test "an unparseable stored value fails" do
      assert UsageMap.load(%{"unit" => "meter", "value" => "abc", "usage" => "road"}) == :error
    end

    test "dumping a non-unit fails" do
      assert UsageMap.dump(nil) == :error
    end

    test "cast, embed_as and equal? delegate to the composite type" do
      assert {:ok, unit} =
               UsageMap.cast(%{"unit" => "meter", "value" => "2.5", "usage" => "road"})

      assert unit.name == "meter"
      assert UsageMap.embed_as(:json) == :self
      assert UsageMap.equal?(meter("2.5"), meter("2.5"))
    end

    # A form need not submit a usage, and string keys are what a form
    # supplies, so the absent key must cast the same way the atom-keyed
    # form always has.
    test "a map without a usage key casts, whichever keys it uses" do
      assert {:ok, from_strings} = UsageMap.cast(%{"unit" => "meter", "value" => "2.5"})
      assert {:ok, from_atoms} = UsageMap.cast(%{unit: "meter", value: "2.5"})

      assert from_strings.usage == nil
      assert from_atoms.usage == nil
      assert from_strings == from_atoms
    end

    test "a map with an explicit nil or empty usage also casts" do
      assert {:ok, explicit_nil} =
               UsageMap.cast(%{"unit" => "meter", "value" => "2.5", "usage" => nil})

      assert {:ok, empty} = UsageMap.cast(%{"unit" => "meter", "value" => "2.5", "usage" => ""})

      assert explicit_nil.usage == nil
      assert empty.usage == nil
    end

    # The guard on the no-usage clause must not send a map that carries
    # an unmatched "usage" back through it.
    test "an unmatched value with a usage key errors rather than recursing" do
      assert UsageMap.cast(%{"unit" => "meter", "value" => [1, 2], "usage" => "road"}) == :error
    end

    test "round trips with usage preserved" do
      original = meter("2.5", usage: "road")
      {:ok, dumped} = UsageMap.dump(original)
      {:ok, loaded} = UsageMap.load(dumped)

      assert loaded.usage == "road"
      assert Decimal.equal?(loaded.value, original.value)
    end
  end
end

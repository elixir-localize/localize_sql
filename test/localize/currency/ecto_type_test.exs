defmodule Localize.Currency.Ecto.TypeTest do
  use ExUnit.Case, async: true

  alias Localize.Currency.Ecto.Type

  describe "type/0" do
    test "stores as text" do
      assert Type.type() == :string
    end
  end

  describe "cast/1" do
    test "casts an atom code" do
      assert Type.cast(:USD) == {:ok, :USD}
    end

    test "casts a string code, upcasing" do
      assert Type.cast("usd") == {:ok, :USD}
    end

    test "casts a currency struct to its code" do
      assert Type.cast(%Localize.Currency{code: :EUR}) == {:ok, :EUR}
    end

    test "casts nil" do
      assert Type.cast(nil) == {:ok, nil}
    end

    test "returns a message for an unknown code" do
      assert Type.cast("ZZZ") == {:error, message: "is not a known currency", value: "ZZZ"}
    end

    test "refuses a value that is not a code" do
      assert Type.cast(42) == :error
    end
  end

  describe "dump/1" do
    test "dumps a code atom to its string" do
      assert Type.dump(:USD) == {:ok, "USD"}
    end

    test "dumps a currency struct" do
      assert Type.dump(%Localize.Currency{code: :JPY}) == {:ok, "JPY"}
    end

    test "dumps nil" do
      assert Type.dump(nil) == {:ok, nil}
    end

    test "refuses an unknown code" do
      assert Type.dump(:ZZZ) == :error
    end
  end

  describe "load/1" do
    test "loads a stored code into the code atom" do
      assert Type.load("USD") == {:ok, :USD}
    end

    test "loads nil" do
      assert Type.load(nil) == {:ok, nil}
    end

    test "refuses stored text that is not a known code" do
      assert Type.load("ZZZ") == :error
    end
  end

  describe "round trips" do
    test "cast, dump and load agree" do
      {:ok, cast} = Type.cast("usd")
      {:ok, dumped} = Type.dump(cast)
      {:ok, loaded} = Type.load(dumped)

      assert cast == :USD
      assert dumped == "USD"
      assert loaded == :USD
    end
  end
end

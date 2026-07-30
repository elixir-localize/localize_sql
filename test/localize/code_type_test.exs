defmodule Localize.CodeTypeTest do
  use ExUnit.Case, async: true

  alias Localize.Script.Ecto.Type, as: Script
  alias Localize.Territory.Ecto.Type, as: Territory

  describe "Territory" do
    test "stores as text" do
      assert Territory.type() == :string
    end

    test "casts an atom or string, including M49 region codes as strings" do
      assert Territory.cast(:US) == {:ok, :US}
      assert Territory.cast("us") == {:ok, :US}
      assert Territory.cast("001") == {:ok, :"001"}
      assert Territory.cast("150") == {:ok, :"150"}
    end

    test "rejects a country-level M49 number, which CLDR keys by alpha-2" do
      assert {:error, message: _} = Territory.cast("840")
    end

    test "refuses a value that is not a code" do
      assert Territory.cast(840) == :error
      assert Territory.cast([:US]) == :error
    end

    test "dumps and loads through the code string" do
      assert Territory.dump(:US) == {:ok, "US"}
      assert Territory.load("US") == {:ok, :US}
    end

    test "casts nil" do
      assert Territory.cast(nil) == {:ok, nil}
    end

    test "rejects an unknown territory" do
      assert {:error, message: message} = Territory.cast(:ZZZZ)
      assert is_binary(message)
      assert Territory.load("ZZZZ") == :error
    end

    test "round trips" do
      {:ok, cast} = Territory.cast("gb")
      {:ok, dumped} = Territory.dump(cast)
      {:ok, loaded} = Territory.load(dumped)

      assert cast == :GB
      assert dumped == "GB"
      assert loaded == :GB
    end
  end

  describe "Script" do
    test "stores as text" do
      assert Script.type() == :string
    end

    test "casts an atom and a string to the code" do
      assert Script.cast(:Latn) == {:ok, :Latn}
      assert Script.cast("Latn") == {:ok, :Latn}
    end

    test "dumps and loads through the code string" do
      assert Script.dump(:Cyrl) == {:ok, "Cyrl"}
      assert Script.load("Cyrl") == {:ok, :Cyrl}
    end

    test "casts nil" do
      assert Script.cast(nil) == {:ok, nil}
    end

    test "rejects an unknown script" do
      assert {:error, message: message} = Script.cast(:Xyzq)
      assert is_binary(message)
      assert Script.load("Xyzq") == :error
    end
  end
end

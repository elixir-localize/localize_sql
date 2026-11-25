defmodule Localize.LanguageTag.Ecto.TypeTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag
  alias Localize.LanguageTag.Ecto.Type

  doctest Localize.LanguageTag.Ecto.Type, only: [equal?: 2]

  describe "type/0" do
    test "stores as text" do
      assert Type.type() == :string
    end
  end

  describe "cast/1" do
    test "casts a locale string into a resolved tag" do
      assert {:ok, %LanguageTag{}} = Type.cast("en-US")
    end

    test "casts a locale atom" do
      assert {:ok, %LanguageTag{}} = Type.cast(:"en-US")
    end

    test "passes a language tag through" do
      {:ok, tag} = Localize.validate_locale("en-US")
      assert Type.cast(tag) == {:ok, tag}
    end

    # The tags are not identical — each preserves the identifier it was
    # asked for in `requested_locale_id` — but they resolve to the same
    # locale and therefore store identically.
    test "canonicalizes so equivalent identifiers store identically" do
      {:ok, underscored} = Type.cast("en_US")
      {:ok, hyphenated} = Type.cast("en-US")

      assert Type.dump(underscored) == Type.dump(hyphenated)
      assert Type.dump(underscored) == {:ok, "en-US"}
    end

    test "casts nil" do
      assert Type.cast(nil) == {:ok, nil}
    end

    test "returns a message for an invalid locale" do
      assert Type.cast("this-is-not-a-locale") ==
               {:error, message: "is not a valid locale", value: "this-is-not-a-locale"}
    end

    test "refuses a value that is neither a tag nor an identifier" do
      assert Type.cast(42) == :error
    end
  end

  describe "dump/1" do
    test "dumps a tag to its canonical string" do
      {:ok, tag} = Localize.validate_locale("en-US")
      assert Type.dump(tag) == {:ok, "en-US"}
    end

    test "preserves -u- extensions in the dumped string" do
      {:ok, tag} = Localize.validate_locale("de-DE-u-co-phonebk")
      assert Type.dump(tag) == {:ok, "de-DE-u-co-phonebk"}
    end

    test "dumps nil" do
      assert Type.dump(nil) == {:ok, nil}
    end
  end

  describe "load/1" do
    test "loads a stored string into a resolved tag" do
      assert {:ok, %LanguageTag{} = tag} = Type.load("zh-Hant-TW")
      assert LanguageTag.to_string(tag) == "zh-Hant-TW"
    end

    test "loads nil" do
      assert Type.load(nil) == {:ok, nil}
    end

    test "refuses stored text that is not a valid locale" do
      assert Type.load("this-is-not-a-locale") == :error
    end
  end

  describe "round trips" do
    test "cast, dump and load preserve the locale" do
      {:ok, cast} = Type.cast("de-DE-u-co-phonebk")
      {:ok, dumped} = Type.dump(cast)
      {:ok, loaded} = Type.load(dumped)

      assert dumped == "de-DE-u-co-phonebk"
      assert loaded == cast
    end
  end

  describe "equal?/2" do
    test "is true for two spellings of one locale" do
      {:ok, cast} = Type.cast("en-au")

      assert Type.equal?(cast, LanguageTag.new!("en-AU"))
      assert Type.equal?("en-au", :"en-AU")
      assert Type.equal?(nil, nil)
    end

    test "is false for two locales, and for nil against a locale" do
      refute Type.equal?(:en, :fr)
      refute Type.equal?(nil, :en)
    end

    test "compares two values that do not dump by ==" do
      assert Type.equal?(42, 42)
      refute Type.equal?(42, "not a locale!")
    end

    test "records no change in a changeset for another spelling of the stored locale" do
      types = %{locale: Type}
      data = %{locale: LanguageTag.new!("en-AU")}

      assert Ecto.Changeset.cast({data, types}, %{locale: "en-au"}, [:locale]).changes == %{}
      assert Ecto.Changeset.cast({data, types}, %{locale: "fr"}, [:locale]).changes != %{}
    end
  end
end

defmodule Localize.Message.Ecto.TypeTest do
  use ExUnit.Case, async: true

  alias Localize.Message.Ecto.Type

  @plural ".input {$count :number}\n.match $count\none {{One item}}\n* {{{$count} items}}"

  describe "type/0" do
    test "stores as text" do
      assert Type.type() == :string
    end
  end

  describe "cast/1" do
    test "keeps a valid message as it is written" do
      for message <- ["Hello", "{{Hello {$name}}}", @plural, "  spaced  "] do
        assert Type.cast(message) == {:ok, message}
      end
    end

    test "takes the source of a parsed message" do
      {:ok, parsed} = Localize.Message.parse(@plural)
      assert Type.cast(parsed) == {:ok, @plural}
    end

    test "refuses a message that is not valid MF2 syntax, with a fixed msgid and the detail" do
      assert {:error, [message: "is not a valid MF2 message: %{detail}", detail: detail]} =
               Type.cast("bad {")

      assert is_binary(detail)
    end

    test "refuses a message that breaks a data-model rule" do
      for message <- [
            ".input {$n :number}\n.match $n\none {{One}}",
            ".local $n = {$n :number}\n{{{$n}}}",
            ".match $n\n* {{x}}"
          ] do
        assert {:error, [message: _msgid, detail: _detail]} = Type.cast(message), inspect(message)
      end
    end

    test "casts nil and refuses other values" do
      assert Type.cast(nil) == {:ok, nil}

      for value <- [42, :hello, %{}, ["Hello"]] do
        assert Type.cast(value) == :error, inspect(value)
      end
    end
  end

  describe "load/1" do
    test "returns the stored text as it is, valid or not, so a row is always readable" do
      assert Type.load(@plural) == {:ok, @plural}
      assert Type.load("bad {") == {:ok, "bad {"}
      assert Type.load(nil) == {:ok, nil}
      assert Type.load(42) == :error
    end
  end

  describe "dump/1" do
    test "writes a valid message, and refuses one that did not pass a changeset" do
      {:ok, parsed} = Localize.Message.parse(@plural)

      assert Type.dump(@plural) == {:ok, @plural}
      assert Type.dump(parsed) == {:ok, @plural}
      assert Type.dump(nil) == {:ok, nil}
      assert Type.dump("bad {") == :error
      assert Type.dump(".input {$n :number}\n.match $n\none {{One}}") == :error
      assert Type.dump(42) == :error
    end
  end

  describe "in a changeset" do
    defp changeset(params) do
      Ecto.Changeset.cast({%{}, %{greeting: Type}}, params, [:greeting])
    end

    test "casts a valid message" do
      changeset = changeset(%{"greeting" => "{{Hello {$name}}}"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :greeting) == "{{Hello {$name}}}"
    end

    test "reports an invalid message as a field error a translator can interpolate" do
      changeset = changeset(%{"greeting" => "Hello {"})

      refute changeset.valid?

      [{message, options}] = Keyword.get_values(changeset.errors, :greeting)
      assert message == "is not a valid MF2 message: %{detail}"
      assert is_binary(options[:detail])

      interpolated =
        Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
          Regex.replace(~r/%\{(\w+)\}/, message, fn _whole, key ->
            options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)

      assert %{greeting: ["is not a valid MF2 message: " <> _detail]} = interpolated
    end
  end
end

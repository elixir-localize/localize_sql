defmodule Localize.Script.Ecto.Type do
  @moduledoc """
  An `Ecto.Type` storing a script as its code in a text column.

  A script is identified by its ISO 15924 code — `:Latn`, `:Cyrl`,
  `:Hant` — and that code is what is stored, in an ordinary text column.
  Values cast and load as the validated code atom, so an unknown script
  is rejected on the way in.

  ### Schema

      # in a migration
      add :script, :string

      # in a schema
      field :script, Localize.Script.Ecto.Type

  ### Casting

  `cast/1` accepts a code as an atom (`:Latn`) or a string (`"Latn"`), and
  validates it against `Localize.validate_script/1`.

  """

  use Ecto.Type

  @invalid_message "is not a known script"

  @impl Ecto.Type
  def type do
    :string
  end

  @impl Ecto.Type
  def cast(nil) do
    {:ok, nil}
  end

  def cast(script) when is_atom(script) or is_binary(script) do
    case Localize.validate_script(script) do
      {:ok, code} -> {:ok, code}
      {:error, _exception} -> {:error, message: @invalid_message, value: script}
    end
  end

  def cast(_script) do
    :error
  end

  @impl Ecto.Type
  def load(nil) do
    {:ok, nil}
  end

  def load(code) when is_binary(code) do
    case Localize.validate_script(code) do
      {:ok, script} -> {:ok, script}
      {:error, _exception} -> :error
    end
  end

  def load(_code) do
    :error
  end

  @impl Ecto.Type
  def dump(nil) do
    {:ok, nil}
  end

  def dump(script) when is_atom(script) or is_binary(script) do
    case Localize.validate_script(script) do
      {:ok, code} -> {:ok, Atom.to_string(code)}
      {:error, _exception} -> :error
    end
  end

  def dump(_script) do
    :error
  end
end

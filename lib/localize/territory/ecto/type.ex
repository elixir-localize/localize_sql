defmodule Localize.Territory.Ecto.Type do
  @moduledoc """
  An `Ecto.Type` storing a territory as its code in a text column.

  A territory is identified by its ISO 3166-1 / CLDR code — `:US`, `:GB`,
  `:"001"` (the world) — and that code is what is stored, in an ordinary
  text column. Values cast and load as the validated code atom, so a
  stored territory can carry a unique index or a `CHECK` constraint like
  any other text, and an unknown territory is rejected on the way in.

  ### Schema

      # in a migration
      add :country, :string

      # in a schema
      field :country, Localize.Territory.Ecto.Type

  ### Casting

  `cast/1` accepts a code as an atom (`:US`) or a string (`"US"`, in any
  case), including UN M49 region codes as strings — `"001"` for the
  world, `"150"` for Europe. Codes are validated against
  `Localize.validate_territory/1`, which resolves CLDR's territory
  aliases, so a country-level M49 number such as `"840"` and an alias
  such as `"UK"` cast to their code (`:US`, `:GB`).

  """

  use Ecto.Type

  @invalid_message "is not a known territory"

  @impl Ecto.Type
  def type do
    :string
  end

  @impl Ecto.Type
  def cast(nil) do
    {:ok, nil}
  end

  def cast(territory) when is_atom(territory) or is_binary(territory) do
    case Localize.validate_territory(territory) do
      {:ok, code} -> {:ok, code}
      {:error, _exception} -> {:error, message: @invalid_message, value: territory}
    end
  end

  def cast(_territory) do
    :error
  end

  @impl Ecto.Type
  def load(nil) do
    {:ok, nil}
  end

  def load(code) when is_binary(code) do
    case Localize.validate_territory(code) do
      {:ok, territory} -> {:ok, territory}
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

  def dump(territory) when is_atom(territory) or is_binary(territory) do
    case Localize.validate_territory(territory) do
      {:ok, code} -> {:ok, Atom.to_string(code)}
      {:error, _exception} -> :error
    end
  end

  def dump(_territory) do
    :error
  end
end

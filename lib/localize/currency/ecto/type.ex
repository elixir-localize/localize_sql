defmodule Localize.Currency.Ecto.Type do
  @moduledoc """
  An `Ecto.Type` storing a currency as its ISO 4217 code in a text column.

  A currency is identified by its code — `:USD`, `:EUR`, `:JPY` — and
  that code is all that needs storing; the currency's name, symbol and
  digits are reference data looked up from the code, not per-row data. So
  the column is ordinary text holding the code, needing no migration
  beyond the column itself.

  Values cast and load as the validated code atom, so a stored currency
  can carry a foreign key, a unique index, or a `CHECK` constraint like
  any other text, and an unknown code is rejected on the way in.

  ### Schema

      # in a migration
      add :currency, :string

      # in a schema
      field :currency, Localize.Currency.Ecto.Type

  ### Casting

  `cast/1` accepts a code as an atom (`:USD`) or string (`"USD"`, in any
  case), or a `t:Localize.Currency.t/0` struct, and validates it against
  `Localize.Currency.validate_currency/1`. An unknown code returns an
  error rather than being stored.

  """

  use Ecto.Type

  alias Localize.Currency

  @invalid_message "is not a known currency"

  @impl Ecto.Type
  def type do
    :string
  end

  @impl Ecto.Type
  def cast(nil) do
    {:ok, nil}
  end

  def cast(%Currency{code: code}) do
    cast(code)
  end

  def cast(currency) when is_atom(currency) or is_binary(currency) do
    case Currency.validate_currency(currency) do
      {:ok, code} -> {:ok, code}
      {:error, _exception} -> {:error, message: @invalid_message, value: currency}
    end
  end

  def cast(_currency) do
    :error
  end

  @impl Ecto.Type
  def load(nil) do
    {:ok, nil}
  end

  def load(code) when is_binary(code) do
    case Currency.validate_currency(code) do
      {:ok, currency_code} -> {:ok, currency_code}
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

  def dump(%Currency{code: code}) do
    dump(code)
  end

  def dump(currency) when is_atom(currency) or is_binary(currency) do
    case Currency.validate_currency(currency) do
      {:ok, code} -> {:ok, Atom.to_string(code)}
      {:error, _exception} -> :error
    end
  end

  def dump(_currency) do
    :error
  end
end

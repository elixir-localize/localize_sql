if Code.ensure_loaded?(Ecto.Type) do
  defmodule Localize.Unit.Ecto.Composite.Type do
    @moduledoc """
    Implements the `Ecto.Type` behaviour for a user-defined Postgres composite
    type called `:cldr_unit`.

    This is the preferred option for Postgres databases since the serialized
    unit value is stored as a decimal number.

    A value is stored in the base unit of its dimension, as
    `Localize.Unit.BaseUnit.base_unit/1` names it: `2 kilometer` is
    stored, and loads, as `2000 meter`, and `100 celsius` as
    `373.15 kelvin`. A comparison or an index on the stored value then
    needs no unit conversion, and since only units of one dimension share a
    base unit, values of different dimensions still cannot be mixed. A cast
    value keeps the unit it was given until it is dumped, and equals its
    base unit form, so a changeset records no change between them.

    """

    @behaviour Ecto.Type

    def type do
      :cldr_unit
    end

    def blank?(_) do
      false
    end

    def load({unit_name, unit_value}) do
      case Localize.Unit.new(unit_value, to_string(unit_name)) do
        {:ok, unit} -> {:ok, unit}
        _error -> :error
      end
    end

    def dump(%Localize.Unit{} = unit) do
      case Localize.Unit.Ecto.Cast.base_unit(unit) do
        {:ok, base} -> {:ok, {base.name, base.value}}
        :error -> :error
      end
    end

    def dump(_) do
      :error
    end

    @dialyzer {:nowarn_function, {:cast, 1}}

    def cast(%Localize.Unit{} = unit) do
      {:ok, unit}
    end

    def cast(%{"unit" => _, "value" => ""}) do
      {:ok, nil}
    end

    def cast(%{"unit" => unit_name, "value" => value})
        when is_binary(unit_name) or is_atom(unit_name) do
      Localize.Unit.Ecto.Cast.cast(unit_name, value, [])
    end

    def cast(%{unit: unit_name, value: value}) do
      cast(%{"unit" => unit_name, "value" => value})
    end

    def cast(_unit) do
      :error
    end

    def embed_as(_), do: :self

    def equal?(%Localize.Unit{} = term1, %Localize.Unit{} = term2) do
      case Localize.Unit.compare(term1, term2) do
        :eq -> true
        _ -> false
      end
    end

    def equal?(term1, term2), do: term1 == term2
  end
end

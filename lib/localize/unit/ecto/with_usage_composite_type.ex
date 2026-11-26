if Code.ensure_loaded?(Ecto.Type) do
  defmodule Localize.UnitWithUsage.Ecto.Composite.Type do
    @moduledoc """
    Implements the `Ecto.Type` behaviour for a user-defined Postgres composite
    type called `:cldr_unit_with_usage`.

    This is the preferred option for Postgres databases since the serialized
    unit value is stored as a decimal number and the unit usage is preserved
    across the round trip.

    A value is stored in the base unit of its dimension, as
    `Localize.Unit.BaseUnit.base_unit/1` names it: `2 kilometer` is
    stored, and loads, as `2000 meter`, and `100 celsius` as
    `373.15 kelvin`. A comparison or an index on the stored value then
    needs no unit conversion, and since only units of one dimension share a
    base unit, values of different dimensions still cannot be mixed. A cast
    value keeps the unit it was given until it is dumped, and equals its
    base unit form, so a changeset records no change between them.

    The usage is kept, so an application can show a loaded value in the
    unit a locale prefers for that usage.

    """

    @behaviour Ecto.Type

    def type do
      :cldr_unit_with_usage
    end

    def blank?(_) do
      false
    end

    def load({unit_name, unit_value, unit_usage}) when unit_usage in [nil, ""] do
      case Localize.Unit.new(unit_value, to_string(unit_name)) do
        {:ok, unit} -> {:ok, unit}
        _error -> :error
      end
    end

    def load({unit_name, unit_value, unit_usage}) do
      case Localize.Unit.new(unit_value, to_string(unit_name), usage: to_string(unit_usage)) do
        {:ok, unit} -> {:ok, unit}
        _error -> :error
      end
    end

    def dump(%Localize.Unit{} = unit) do
      case Localize.Unit.Ecto.Cast.base_unit(unit) do
        {:ok, base} -> {:ok, {base.name, base.value, base.usage && to_string(base.usage)}}
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

    def cast(%{"unit" => unit_name, "value" => value, "usage" => usage})
        when is_binary(unit_name) or is_atom(unit_name) do
      options = Localize.Unit.Ecto.Cast.usage_options(usage)
      Localize.Unit.Ecto.Cast.cast(unit_name, value, options)
    end

    # A form need not submit a usage. The atom-keyed clause below has
    # always tolerated its absence; this does the same for string keys,
    # which is what an HTML form supplies. The guard is what stops a map
    # that already carries an unmatched "usage" from recursing here.
    def cast(%{"unit" => unit_name, "value" => value} = unit)
        when not is_map_key(unit, "usage") do
      cast(%{"unit" => unit_name, "value" => value, "usage" => nil})
    end

    def cast(%{unit: unit_name, value: value} = unit) do
      cast(%{"unit" => unit_name, "value" => value, "usage" => Map.get(unit, :usage)})
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

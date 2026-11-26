defmodule Localize.Unit.Ecto.Cast do
  @moduledoc false

  # Casting and loading shared by the unit Ecto types. A cast error is a
  # fixed msgid with what was wrong as a binding, so an application's
  # `translate_error/1` can translate it.

  @invalid_value "is not a valid unit value"
  @invalid_unit "is not a valid unit of measure: %{detail}"

  @doc false
  @spec cast(term(), term(), Keyword.t()) :: {:ok, Localize.Unit.t()} | {:error, Keyword.t()}
  def cast(unit_name, value, options) do
    case decimal(value) do
      {:ok, decimal} -> new_unit(unit_name, decimal, options)
      :error -> {:error, message: @invalid_value, value: value}
    end
  end

  @doc false
  @spec load(term(), term(), Keyword.t()) :: {:ok, Localize.Unit.t()} | :error
  def load(unit_name, value, options) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> loaded_unit(unit_name, decimal, options)
      _other -> :error
    end
  end

  def load(unit_name, value, options) when is_integer(value) do
    loaded_unit(unit_name, value, options)
  end

  def load(_unit_name, _value, _options) do
    :error
  end

  @doc false
  # A unit in the base unit of its dimension, as the unit types store it:
  # `2 kilometer` is `2000 meter`, `100 celsius` is `373.15 kelvin`. A
  # comparison or an index on the stored value then needs no unit
  # conversion, and only units of one dimension share a base unit, so
  # values of different dimensions still cannot be mixed. The value is a
  # decimal before converting, since an integer would convert to a float.
  # `Localize.Unit.convert/2` drops the usage, so the source's is kept.
  @spec base_unit(Localize.Unit.t()) :: {:ok, Localize.Unit.t()} | :error
  def base_unit(%Localize.Unit{} = unit) do
    with {:ok, value} <- decimal(unit.value),
         {:ok, base_name} <- base_unit_name(unit.name),
         {:ok, base} <- convert(%{unit | value: value}, base_name) do
      {:ok, %{base | usage: unit.usage}}
    end
  end

  @doc false
  @spec usage_options(term()) :: Keyword.t()
  def usage_options(usage) when usage in [nil, ""] do
    []
  end

  def usage_options(usage) do
    [usage: to_string(usage)]
  end

  defp new_unit(unit_name, value, options) do
    case Localize.Unit.new(value, to_string(unit_name), options) do
      {:ok, unit} ->
        {:ok, unit}

      {:error, exception} ->
        {:error, message: @invalid_unit, detail: Exception.message(exception)}
    end
  end

  defp loaded_unit(unit_name, value, options) do
    case Localize.Unit.new(value, to_string(unit_name), options) do
      {:ok, unit} -> {:ok, unit}
      {:error, _exception} -> :error
    end
  end

  defp base_unit_name(unit_name) do
    case Localize.Unit.BaseUnit.base_unit(unit_name) do
      {:ok, base_name} -> {:ok, base_name}
      {:error, _reason} -> :error
    end
  end

  defp convert(unit, base_name) do
    case Localize.Unit.convert(unit, base_name) do
      {:ok, base} -> {:ok, base}
      {:error, _exception} -> :error
    end
  end

  # A float is converted exactly as it prints; `Decimal.new/1` raises on one.
  defp decimal(value) when is_integer(value) do
    {:ok, Decimal.new(value)}
  end

  defp decimal(value) when is_float(value) do
    {:ok, Decimal.from_float(value)}
  end

  defp decimal(%Decimal{} = value) do
    {:ok, value}
  end

  defp decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _other -> :error
    end
  end

  defp decimal(_value) do
    :error
  end
end

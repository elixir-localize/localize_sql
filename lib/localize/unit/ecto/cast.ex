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

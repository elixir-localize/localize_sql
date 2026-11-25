if Code.ensure_loaded?(Postgrex.Range) do
  defmodule Localize.Ecto.Type.IntegerRange do
    @moduledoc """
    An `Ecto.Type` storing an Elixir integer `t:Range.t/0` in a PostgreSQL
    `int8range` column.

    A range such as `1..10` stores and loads as itself, so a bounded span
    of integers is a first-class value in a schema rather than a pair of
    columns. `int8range` is a built-in PostgreSQL type, so no migration
    beyond the column is needed, and the column can be queried with the
    range operators (`@>`, `&&`) and indexed with a GiST index.

    ### Schema

        # in a migration
        add :levels, :int8range

        # in a schema
        field :levels, Localize.Ecto.Type.IntegerRange

    ### Semantics

    Elixir ranges are inclusive of both ends, so `1..10` covers `1`
    through `10`; it is stored as the PostgreSQL range `[1,10]` and read
    back as `1..10` regardless of the bound form PostgreSQL canonicalizes
    to (it stores `int8range` as `[lower, upper)`).

    Only ascending unit-step ranges are storable — a range carrying a
    step (`1..10//2`) or descending (an empty range like `10..1//1`) has
    no `int8range` equivalent and is rejected on cast and dump.

    """

    use Ecto.Type

    @invalid_message "is not an ascending integer range with a step of 1"

    @impl Ecto.Type
    def type do
      :int8range
    end

    @impl Ecto.Type
    def cast(nil) do
      {:ok, nil}
    end

    def cast(%Range{first: first, last: last, step: 1} = range) when first <= last do
      {:ok, range}
    end

    def cast(%Range{} = range) do
      {:error, message: @invalid_message, value: range}
    end

    def cast(_range) do
      :error
    end

    @impl Ecto.Type
    def load(nil) do
      {:ok, nil}
    end

    def load(%Postgrex.Range{lower: lower, upper: upper} = range)
        when is_integer(lower) and is_integer(upper) do
      first =
        if range.lower_inclusive do
          lower
        else
          lower + 1
        end

      last =
        if range.upper_inclusive do
          upper
        else
          upper - 1
        end

      {:ok, first..last}
    end

    def load(%Postgrex.Range{}) do
      # An unbounded or empty range has no Elixir Range equivalent.
      :error
    end

    def load(_value) do
      :error
    end

    @impl Ecto.Type
    def dump(nil) do
      {:ok, nil}
    end

    def dump(%Range{first: first, last: last, step: 1}) when first <= last do
      {:ok,
       %Postgrex.Range{
         lower: first,
         upper: last,
         lower_inclusive: true,
         upper_inclusive: true
       }}
    end

    def dump(_range) do
      :error
    end
  end
end

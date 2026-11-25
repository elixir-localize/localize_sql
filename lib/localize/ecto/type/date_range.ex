if Code.ensure_loaded?(Postgrex.Range) do
  defmodule Localize.Ecto.Type.DateRange do
    @moduledoc """
    An `Ecto.Type` storing an Elixir `t:Date.Range.t/0` in a PostgreSQL
    `daterange` column.

    A range such as `Date.range(~D[2024-01-01], ~D[2024-12-31])` stores
    and loads as itself, so a span of dates is a first-class value in a
    schema. `daterange` is a built-in PostgreSQL type, so no migration
    beyond the column is needed, and the column can be queried with the
    range operators (`@>`, `&&`) — including an exclusion constraint that
    forbids overlapping spans — and indexed with a GiST index.

    ### Schema

        # in a migration
        add :period, :daterange

        # in a schema
        field :period, Localize.Ecto.Type.DateRange

    ### Semantics

    `Date.Range` is inclusive of both ends, so
    `Date.range(~D[2024-01-01], ~D[2024-12-31])` covers the whole year;
    it is stored as the PostgreSQL range `[2024-01-01, 2024-12-31]` and
    read back inclusive regardless of the bound form PostgreSQL
    canonicalizes to (it stores `daterange` as `[lower, upper)`).

    Only ascending day-step ranges are storable — a range carrying a step
    other than one day, or a descending one, has no `daterange`
    equivalent and is rejected on cast and dump.

    """

    use Ecto.Type

    @invalid_message "is not an ascending date range with a step of one day"

    @impl Ecto.Type
    def type do
      :daterange
    end

    @impl Ecto.Type
    def cast(nil) do
      {:ok, nil}
    end

    def cast(%Date.Range{step: 1} = range) do
      if ascending?(range) do
        {:ok, range}
      else
        {:error, message: @invalid_message, value: range}
      end
    end

    def cast(%Date.Range{} = range) do
      {:error, message: @invalid_message, value: range}
    end

    def cast(_range) do
      :error
    end

    @impl Ecto.Type
    def load(nil) do
      {:ok, nil}
    end

    def load(%Postgrex.Range{lower: %Date{} = lower, upper: %Date{} = upper} = range) do
      first =
        if range.lower_inclusive do
          lower
        else
          Date.add(lower, 1)
        end

      last =
        if range.upper_inclusive do
          upper
        else
          Date.add(upper, -1)
        end

      {:ok, Date.range(first, last)}
    end

    def load(%Postgrex.Range{}) do
      # An unbounded or empty range has no Date.Range equivalent.
      :error
    end

    def load(_value) do
      :error
    end

    @impl Ecto.Type
    def dump(nil) do
      {:ok, nil}
    end

    def dump(%Date.Range{step: 1} = range) do
      if ascending?(range) do
        {:ok,
         %Postgrex.Range{
           lower: range.first,
           upper: range.last,
           lower_inclusive: true,
           upper_inclusive: true
         }}
      else
        :error
      end
    end

    def dump(_range) do
      :error
    end

    defp ascending?(%Date.Range{first: first, last: last}) do
      Date.compare(first, last) != :gt
    end
  end
end

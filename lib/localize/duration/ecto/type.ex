if Code.ensure_loaded?(Postgrex.Interval) do
  defmodule Localize.Duration.Ecto.Type do
    @moduledoc """
    An `Ecto.Type` storing a `t:Localize.Duration.t/0` in a PostgreSQL
    `interval` column.

    A `Localize.Duration` is an amount of time in calendar units — a year,
    three months, two days — and `interval` is the PostgreSQL type for
    exactly that. Storing one as an `interval` rather than a number of
    seconds keeps the calendar meaning that "one month" carries (a month
    is not always thirty days), and lets the database add an interval to a
    date or sum a column of them.

    ### Schema

        # in a migration
        add :billing_period, :interval

        # in a schema
        field :billing_period, Localize.Duration.Ecto.Type

    ### Normalization

    PostgreSQL `interval` keeps three components — months, days and time —
    so the units within each component are interchangeable: a duration of
    ninety minutes is stored as, and loaded back as, one hour and thirty
    minutes, and thirteen months as one year and one month. Durations that
    are already in their normal form round-trip unchanged. The day and
    month components are kept distinct — a month is never folded into days
    — because PostgreSQL applies them separately when an interval is added
    to a date.

    """

    use Ecto.Type

    alias Localize.Duration

    @seconds_per_minute 60
    @seconds_per_hour 3600
    @months_per_year 12

    @impl Ecto.Type
    def type do
      :interval
    end

    @impl Ecto.Type
    def cast(nil) do
      {:ok, nil}
    end

    def cast(%Duration{} = duration) do
      {:ok, duration}
    end

    def cast(_duration) do
      :error
    end

    @impl Ecto.Type
    def load(nil) do
      {:ok, nil}
    end

    def load(%Postgrex.Interval{months: months, days: days, secs: secs, microsecs: microsecs}) do
      {:ok,
       %Duration{
         year: div(months, @months_per_year),
         month: rem(months, @months_per_year),
         day: days,
         hour: div(secs, @seconds_per_hour),
         minute: div(rem(secs, @seconds_per_hour), @seconds_per_minute),
         second: rem(secs, @seconds_per_minute),
         microsecond: microsecond(microsecs)
       }}
    end

    def load(_value) do
      :error
    end

    # PostgreSQL does not store the fractional-second precision, so a
    # value with no microseconds takes precision 0 and one with
    # microseconds takes the full 6 digits; the microsecond value itself
    # always round-trips.
    defp microsecond(0), do: {0, 0}
    defp microsecond(microsecs), do: {microsecs, 6}

    @impl Ecto.Type
    def dump(nil) do
      {:ok, nil}
    end

    def dump(%Duration{} = duration) do
      {microsecs, _precision} = duration.microsecond

      {:ok,
       %Postgrex.Interval{
         months: duration.year * @months_per_year + duration.month,
         days: duration.day,
         secs:
           duration.hour * @seconds_per_hour + duration.minute * @seconds_per_minute +
             duration.second,
         microsecs: microsecs
       }}
    end

    def dump(_duration) do
      :error
    end

    @impl Ecto.Type
    @doc """
    Returns whether two durations store the same interval.

    An `interval` keeps months, days and time, so ninety minutes is stored
    and loaded as one hour and thirty minutes. The two are not `==`, but
    they are the same interval, so a changeset that casts one over the
    other records no change.

    ### Arguments

    * `left` is a duration or `nil`.

    * `right` is a duration or `nil`.

    ### Returns

    * `true` when both dump to the same interval, or are `==`, or

    * `false` otherwise.

    ### Examples

        iex> Localize.Duration.Ecto.Type.equal?(%Localize.Duration{minute: 90}, %Localize.Duration{hour: 1, minute: 30})
        true

        iex> Localize.Duration.Ecto.Type.equal?(%Localize.Duration{minute: 90}, %Localize.Duration{minute: 91})
        false

    """
    @spec equal?(term(), term()) :: boolean()
    def equal?(left, right) do
      case {dump(left), dump(right)} do
        {{:ok, same}, {:ok, same}} -> true
        _different -> left == right
      end
    end
  end
end

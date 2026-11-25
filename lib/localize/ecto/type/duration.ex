if Code.ensure_loaded?(Postgrex.Interval) do
  defmodule Localize.Ecto.Type.Duration do
    @moduledoc """
    An `Ecto.Type` storing an Elixir `t:Duration.t/0` in a PostgreSQL
    `interval` column.

    Elixir's `Duration` is an amount of time in calendar units, which is
    exactly what the PostgreSQL `interval` type stores. Storing a duration
    as an `interval` rather than a number of seconds keeps its calendar
    meaning — "one month" is a month, not thirty days — and lets the
    database add it to a date or sum a column of them.

    For the localized `t:Localize.Duration.t/0` struct, see
    `Localize.Duration.Ecto.Type`.

    ### Schema

        # in a migration
        add :retention, :interval

        # in a schema
        field :retention, Localize.Ecto.Type.Duration

    ### Normalization

    PostgreSQL `interval` keeps three components — months, days and time —
    so units within a component are interchangeable: ninety minutes loads
    back as one hour and thirty minutes, and a week loads back as seven
    days (`interval` has no separate week). The month and day components
    are kept distinct, because PostgreSQL applies them separately when an
    interval is added to a date. A duration already in this normal form
    round-trips unchanged.

    """

    use Ecto.Type

    @seconds_per_minute 60
    @seconds_per_hour 3600
    @days_per_week 7
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
       Duration.new!(
         year: div(months, @months_per_year),
         month: rem(months, @months_per_year),
         day: days,
         hour: div(secs, @seconds_per_hour),
         minute: div(rem(secs, @seconds_per_hour), @seconds_per_minute),
         second: rem(secs, @seconds_per_minute),
         microsecond: microsecond(microsecs)
       )}
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
         days: duration.day + duration.week * @days_per_week,
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

    * `left` and `right` are durations or `nil`.

    ### Returns

    * `true` when both dump to the same interval, or are `==`, or

    * `false` otherwise.

    ### Examples

        iex> Localize.Ecto.Type.Duration.equal?(Duration.new!(minute: 90), Duration.new!(hour: 1, minute: 30))
        true

        iex> Localize.Ecto.Type.Duration.equal?(Duration.new!(minute: 90), Duration.new!(minute: 91))
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

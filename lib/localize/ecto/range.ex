defmodule Localize.Ecto.Range do
  @moduledoc """
  Query expressions for PostgreSQL range types.

  PostgreSQL stores an interval — a span of numbers, dates or times — as
  a single value with its own operators, so a query can ask whether two
  spans overlap without comparing four endpoints by hand. Postgrex
  already encodes and decodes every built-in range type as a
  `t:Postgrex.Range.t/0`, so no Ecto type is needed to store one. What
  this module adds is the query side: the range operators as macros that
  read as query syntax rather than as `fragment/2` calls.

  ### Range types

  PostgreSQL provides `int4range`, `int8range` and `numrange` over
  numbers, and `daterange`, `tsrange` and `tstzrange` over dates and
  timestamps. Each has a multirange counterpart holding a set of
  disjoint spans. There is no built-in range over time of day;
  `Localize.Ecto.Range.Migration.create_time_range/1` creates one.

  A range column is declared with the PostgreSQL type name, and Postgrex
  reads it back as a `t:Postgrex.Range.t/0` with no Ecto type needed:

      # in a migration
      add :period, :tstzrange

  ### Naming

  The set operations are `range_union/2`, `range_intersection/2` and
  `range_difference/2` rather than the bare names. They combine two
  range *values* inside a row, which is a different operation from
  `Ecto.Query.union/2`, `Ecto.Query.intersect/2` and
  `Ecto.Query.except/2` combining the *result sets* of two queries —
  and `union/2` would otherwise be ambiguous with the `Ecto.Query`
  import that every query module already has. For the same reason the
  bound accessors are `lower_bound/1` and `upper_bound/1`, leaving
  `lower/1` and `upper/1` to the locale-aware case mapping of
  `Localize.Ecto.Postgres`.

  ### Bounds

  A range has an inclusive or exclusive bound at each end, and either
  end may be unbounded (`nil`). PostgreSQL normalizes the discrete
  ranges — `int4range`, `int8range` and `daterange` — to `[)` form, so
  the value read back may not carry the bounds it was written with even
  though it denotes the same span.

  ### Examples

      import Ecto.Query
      import Localize.Ecto.Range

      # Bookings that overlap a requested period
      from b in Booking, where: overlaps(b.period, ^requested)

      # Bookings covering a particular day
      from b in Booking, where: contains(b.period, ^~D[2026-07-30])

  """

  @doc """
  Tests whether a range contains a value or another range.

  Expands to PostgreSQL's `@>` operator, which accepts either an element
  of the range's subtype or another range of the same type.

  ### Arguments

  * `range` is an Ecto query expression that evaluates to a range.

  * `value` is an element of the range's subtype, or another range. A
    pinned expression (`^value`) is also accepted.

  ### Returns

  * A query fragment `range @> value`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", where: contains(b.period, ^~D[2026-07-30])
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro contains(range, value) do
    quote do
      fragment("? @> ?", unquote(range), unquote(value))
    end
  end

  @doc """
  Tests whether a value or range is contained by a range.

  Expands to PostgreSQL's `<@` operator. This is `contains/2` with the
  arguments reversed, and reads better when the contained value is the
  subject of the query.

  ### Arguments

  * `value` is an element of the range's subtype, or another range. A
    pinned expression (`^value`) is also accepted.

  * `range` is an Ecto query expression that evaluates to a range.

  ### Returns

  * A query fragment `value <@ range`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", where: contained_by(^~D[2026-07-30], b.period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro contained_by(value, range) do
    quote do
      fragment("? <@ ?", unquote(value), unquote(range))
    end
  end

  @doc """
  Tests whether two ranges share any point.

  Expands to PostgreSQL's `&&` operator. Two ranges that merely touch —
  one ending exactly where the other begins, with one bound exclusive —
  do not overlap; `adjacent/2` tests for that.

  ### Arguments

  * `left` and `right` are Ecto query expressions that evaluate to
    ranges of the same type. A pinned expression (`^range`) is also
    accepted.

  ### Returns

  * A query fragment `left && right`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", where: overlaps(b.period, b.requested)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro overlaps(left, right) do
    quote do
      fragment("? && ?", unquote(left), unquote(right))
    end
  end

  @doc """
  Tests whether two ranges are adjacent.

  Expands to PostgreSQL's `-|-` operator. Adjacent ranges meet without
  overlapping and without leaving a gap, so their union is a single
  range.

  ### Arguments

  * `left` and `right` are Ecto query expressions that evaluate to
    ranges of the same type.

  ### Returns

  * A query fragment `left -|- right`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", where: adjacent(b.period, b.next_period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro adjacent(left, right) do
    quote do
      fragment("? -|- ?", unquote(left), unquote(right))
    end
  end

  @doc """
  Tests whether one range lies entirely before another.

  Expands to PostgreSQL's `<<` operator.

  ### Arguments

  * `left` and `right` are Ecto query expressions that evaluate to
    ranges of the same type.

  ### Returns

  * A query fragment `left << right`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", where: strictly_before(b.period, b.next_period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro strictly_before(left, right) do
    quote do
      fragment("? << ?", unquote(left), unquote(right))
    end
  end

  @doc """
  Tests whether one range lies entirely after another.

  Expands to PostgreSQL's `>>` operator.

  ### Arguments

  * `left` and `right` are Ecto query expressions that evaluate to
    ranges of the same type.

  ### Returns

  * A query fragment `left >> right`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", where: strictly_after(b.period, b.previous_period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro strictly_after(left, right) do
    quote do
      fragment("? >> ?", unquote(left), unquote(right))
    end
  end

  @doc """
  Returns the union of two ranges.

  Expands to PostgreSQL's `+` operator. The server raises unless the
  ranges overlap or are adjacent, since the union would otherwise not be
  a single range. Aggregate a column of arbitrary ranges with
  `range_agg/1` instead, which returns a multirange.

  ### Arguments

  * `left` and `right` are Ecto query expressions that evaluate to
    ranges of the same type.

  ### Returns

  * A query fragment `left + right`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", select: range_union(b.period, b.next_period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro range_union(left, right) do
    quote do
      fragment("? + ?", unquote(left), unquote(right))
    end
  end

  @doc """
  Returns the intersection of two ranges.

  Expands to PostgreSQL's `*` operator. The result is the empty range
  when the two do not overlap.

  ### Arguments

  * `left` and `right` are Ecto query expressions that evaluate to
    ranges of the same type.

  ### Returns

  * A query fragment `left * right`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", select: range_intersection(b.period, b.requested)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro range_intersection(left, right) do
    quote do
      fragment("? * ?", unquote(left), unquote(right))
    end
  end

  @doc """
  Returns the difference of two ranges.

  Expands to PostgreSQL's `-` operator. The server raises if removing
  the second range would split the first into two, since the result
  would not be a single range.

  ### Arguments

  * `left` and `right` are Ecto query expressions that evaluate to
    ranges of the same type.

  ### Returns

  * A query fragment `left - right`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", select: range_difference(b.period, b.blackout)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro range_difference(left, right) do
    quote do
      fragment("? - ?", unquote(left), unquote(right))
    end
  end

  @doc """
  Returns the lower bound of a range.

  Expands to PostgreSQL's `lower()` function, which returns `NULL` when
  the range has no lower bound or is empty. Named `lower_bound` rather
  than `lower` so that this module and `Localize.Ecto.Postgres`, whose
  `lower/1` is locale-aware case mapping, can both be imported.

  ### Arguments

  * `range` is an Ecto query expression that evaluates to a range.

  ### Returns

  * A query fragment `lower(range)`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", select: lower_bound(b.period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro lower_bound(range) do
    quote do
      fragment("lower(?)", unquote(range))
    end
  end

  @doc """
  Returns the upper bound of a range.

  Expands to PostgreSQL's `upper()` function, which returns `NULL` when
  the range has no upper bound or is empty. See `lower_bound/1` on the
  naming.

  ### Arguments

  * `range` is an Ecto query expression that evaluates to a range.

  ### Returns

  * A query fragment `upper(range)`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", select: upper_bound(b.period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro upper_bound(range) do
    quote do
      fragment("upper(?)", unquote(range))
    end
  end

  @doc """
  Tests whether a range is empty.

  Expands to PostgreSQL's `isempty()` function. A range is empty when it
  contains no points, which is what a degenerate range such as
  `numrange(1,1)` normalizes to.

  ### Arguments

  * `range` is an Ecto query expression that evaluates to a range.

  ### Returns

  * A query fragment `isempty(range)`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", where: is_empty(b.period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro is_empty(range) do
    quote do
      fragment("isempty(?)", unquote(range))
    end
  end

  @doc """
  Aggregates a column of ranges into a multirange.

  Expands to PostgreSQL's `range_agg()` aggregate, which unions the
  ranges of the group and returns a `t:Postgrex.Multirange.t/0` holding
  the disjoint spans that result. Unlike `union/2` the ranges need not
  overlap or be adjacent. Requires PostgreSQL 14 or later.

  ### Arguments

  * `range` is an Ecto query expression that evaluates to a range.

  ### Returns

  * A query fragment `range_agg(range)`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", select: range_agg(b.period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro range_agg(range) do
    quote do
      fragment("range_agg(?)", unquote(range))
    end
  end

  @doc """
  Aggregates a column of ranges into their common intersection.

  Expands to PostgreSQL's `range_intersect_agg()` aggregate. Requires
  PostgreSQL 14 or later.

  ### Arguments

  * `range` is an Ecto query expression that evaluates to a range.

  ### Returns

  * A query fragment `range_intersect_agg(range)`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from b in "bookings", select: range_intersect_agg(b.period)
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro range_intersect_agg(range) do
    quote do
      fragment("range_intersect_agg(?)", unquote(range))
    end
  end
end

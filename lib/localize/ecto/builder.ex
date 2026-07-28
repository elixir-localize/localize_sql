defmodule Localize.Ecto.Builder do
  @moduledoc false

  # Shared quoted-expression builders for the adapter-specific query
  # macro modules (`Localize.Ecto.Postgres`, `Localize.Ecto.SQLite3` and
  # the `Localize.Ecto` compatibility module). Ecto requires the SQL of
  # a fragment to be a compile-time literal, so the adapter cannot be
  # chosen at runtime; each adapter module supplies its own SQL and
  # shares the surrounding AST construction from here.

  @comparison_operators [:<, :>, :<=, :>=, :==, :!=]

  # A comparison collates its right-hand operand. Both PostgreSQL and
  # SQLite apply the collation to the whole comparison, since COLLATE
  # binds tighter than any comparison operator.
  def collate({operator, _meta, [left, right]}, resolver)
      when operator in @comparison_operators do
    sql = "? #{sql_operator(operator)} ? COLLATE ?"

    quote do
      fragment(unquote(sql), unquote(left), unquote(right), identifier(^unquote(resolver)))
    end
  end

  def collate(expression, resolver) do
    quote do
      fragment("? COLLATE ?", unquote(expression), identifier(^unquote(resolver)))
    end
  end

  # PostgreSQL's lower(), upper() and initcap() take their case mapping
  # from the collation of their argument, so the collation is attached
  # to the expression as an identifier.
  def postgres_case(function, expression, resolver) do
    sql = "#{function}(? COLLATE ?)"

    quote do
      fragment(unquote(sql), unquote(expression), identifier(^unquote(resolver)))
    end
  end

  # SQLite's COLLATE affects comparison only and never case mapping, so
  # case conversion goes through the two-argument ICU functions the
  # localize_icu extension registers. The locale is an ordinary string
  # argument there, so it binds as a query parameter rather than being
  # interpolated as an identifier.
  def sqlite_case(function, expression, resolver) do
    sql = "#{function}(?, ?)"

    quote do
      fragment(unquote(sql), unquote(expression), ^unquote(resolver))
    end
  end

  # The locale argument of the macros is evaluated as an ordinary
  # expression, not as a query expression, so a pin is not required.
  # Accept one anyway since pinning runtime values is idiomatic inside
  # Ecto queries.
  def unpin({:^, _meta, [expression]}), do: expression
  def unpin(expression), do: expression

  defp sql_operator(:==), do: "="
  defp sql_operator(:!=), do: "<>"
  defp sql_operator(operator), do: Atom.to_string(operator)
end

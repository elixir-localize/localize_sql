defmodule Localize.Ecto.TaggedDecimal.DDL do
  @moduledoc """
  Generates the SQL that installs a tagged decimal type in PostgreSQL.

  A tagged decimal — described by a `t:Localize.Ecto.TaggedDecimal.t/0`
  specification — is stored as a composite type pairing a tag with a
  decimal, such as `money_with_currency(currency_code, amount)` or
  `cldr_unit(unit, value)`. This module returns the SQL creating that
  type together with the aggregate functions and operators that make it
  usable in queries.

  Aggregates over a tagged decimal are *tag-guarded*: summing a column
  whose rows carry different tags raises rather than returning a
  meaningless number. The generated functions compare the tag of each
  incoming row against the tag accumulated so far and raise SQLSTATE
  `22033` (`invalid_parameter_value`) on a mismatch, so a query that adds
  euros to yen fails in the database rather than silently succeeding.

  The SQL is generated from the specification rather than kept as static
  files so that one implementation serves every domain. The names of the
  composite type, its fields and the generated functions come from the
  specification, because a deployed database already contains them and an
  aggregate must name the same fields as the type it was created against.

  ### Statements

  Each function returns one or more SQL statements in a single string,
  separated by two blank lines. `execute/1,2` and `execute_each/1,2`
  wrap them for use in an Ecto migration — `execute_each/1,2` emits one
  `execute` per statement, which is what a migration needs when the
  statements must run in order.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.create_type(spec)
      "CREATE TYPE public.cldr_unit AS (unit varchar, value numeric);"

  """

  alias Localize.Ecto.TaggedDecimal

  @statement_separator "\n\n\n"

  @doc """
  Returns the SQL creating the composite type.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statement as a string.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "money_with_currency", tag_field: "currency_code",
      ...>   value_field: "amount", function_prefix: "money",
      ...>   tag_description: "currency code"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.create_type(spec)
      "CREATE TYPE public.money_with_currency AS (currency_code varchar, amount numeric);"

  """
  @spec create_type(TaggedDecimal.t()) :: String.t()
  def create_type(%TaggedDecimal{} = spec) do
    fields =
      Enum.map_join(TaggedDecimal.fields(spec), ", ", fn {name, type} -> "#{name} #{type}" end)

    "CREATE TYPE public.#{spec.type_name} AS (#{fields});"
  end

  @doc """
  Returns the SQL dropping the composite type.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statement as a string.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.drop_type(spec)
      "DROP TYPE public.cldr_unit;"

  """
  @spec drop_type(TaggedDecimal.t()) :: String.t()
  def drop_type(%TaggedDecimal{} = spec) do
    "DROP TYPE public.#{spec.type_name};"
  end

  @doc """
  Returns the SQL defining a tag-guarded `sum` aggregate.

  Three statements: the state function, the combine function that makes
  the aggregate safe under parallel query, and the aggregate itself.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.define_sum_function(spec) =~ "CREATE OR REPLACE AGGREGATE sum(cldr_unit)"
      true

  """
  @spec define_sum_function(TaggedDecimal.t()) :: String.t()
  def define_sum_function(%TaggedDecimal{} = spec) do
    state_function = TaggedDecimal.function_name(spec, :sum_state)
    combine_function = TaggedDecimal.function_name(spec, :sum_combine)

    join([
      sum_state_function(spec, state_function),
      sum_combine_function(spec, combine_function),
      """
      CREATE OR REPLACE AGGREGATE sum(#{spec.type_name})
      (
        sfunc = #{state_function},
        stype = #{spec.type_name},
        combinefunc = #{combine_function},
        parallel = SAFE
      );
      """
    ])
  end

  @doc """
  Returns the SQL dropping the `sum` aggregate and its functions.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.drop_sum_function(spec) =~ "DROP AGGREGATE IF EXISTS sum(cldr_unit);"
      true

  """
  @spec drop_sum_function(TaggedDecimal.t()) :: String.t()
  def drop_sum_function(%TaggedDecimal{} = spec) do
    join([
      "DROP AGGREGATE IF EXISTS sum(#{spec.type_name});",
      drop_function(spec, :sum_state, [spec.type_name, spec.type_name]),
      drop_function(spec, :sum_combine, [spec.type_name, spec.type_name])
    ])
  end

  @doc """
  Returns the SQL defining tag-guarded `min` and `max` aggregates.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.define_minmax_functions(spec) =~ "AGGREGATE min(cldr_unit)"
      true

  """
  @spec define_minmax_functions(TaggedDecimal.t()) :: String.t()
  def define_minmax_functions(%TaggedDecimal{} = spec) do
    join(Enum.flat_map([min: "<", max: ">"], &extremum_statements(spec, &1)))
  end

  @doc """
  Returns the SQL dropping the `min` and `max` aggregates and their
  functions.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.drop_minmax_functions(spec) =~ "DROP AGGREGATE IF EXISTS max(cldr_unit);"
      true

  """
  @spec drop_minmax_functions(TaggedDecimal.t()) :: String.t()
  def drop_minmax_functions(%TaggedDecimal{} = spec) do
    join(
      Enum.flat_map([:min, :max], fn extremum ->
        [
          "DROP AGGREGATE IF EXISTS #{extremum}(#{spec.type_name});",
          drop_function(spec, :"#{extremum}_state", [spec.type_name, spec.type_name]),
          drop_function(spec, :"#{extremum}_combine", [spec.type_name, spec.type_name])
        ]
      end)
    )
  end

  @doc """
  Returns the SQL defining a tag-guarded `avg` aggregate.

  The aggregate accumulates into an intermediate composite type holding
  a running sum and count, which the final function divides. That type is
  created by this SQL and removed by `drop_avg_function/1`.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.define_avg_function(spec) =~ "CREATE TYPE public.unit_avg_state"
      true

  """
  @spec define_avg_function(TaggedDecimal.t()) :: String.t()
  def define_avg_function(%TaggedDecimal{} = spec) do
    state_type = TaggedDecimal.function_name(spec, :avg_state_type)
    state_function = TaggedDecimal.function_name(spec, :avg_state)
    combine_function = TaggedDecimal.function_name(spec, :avg_combine)
    final_function = TaggedDecimal.function_name(spec, :avg_final)

    join([
      avg_state_type(spec, state_type),
      avg_state_function(spec, state_type, state_function),
      avg_combine_function(spec, state_type, combine_function),
      avg_final_function(spec, state_type, final_function),
      """
      CREATE OR REPLACE AGGREGATE avg(#{spec.type_name})
      (
        sfunc = #{state_function},
        stype = #{state_type},
        combinefunc = #{combine_function},
        finalfunc = #{final_function},
        parallel = SAFE
      );
      """
    ])
  end

  @doc """
  Returns the SQL dropping the `avg` aggregate, its functions and its
  intermediate state type.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.drop_avg_function(spec) =~ "DROP TYPE IF EXISTS public.unit_avg_state;"
      true

  """
  @spec drop_avg_function(TaggedDecimal.t()) :: String.t()
  def drop_avg_function(%TaggedDecimal{} = spec) do
    state_type = TaggedDecimal.function_name(spec, :avg_state_type)

    join([
      "DROP AGGREGATE IF EXISTS avg(#{spec.type_name});",
      drop_function(spec, :avg_state, [state_type, spec.type_name]),
      drop_function(spec, :avg_combine, [state_type, state_type]),
      drop_function(spec, :avg_final, [state_type]),
      "DROP TYPE IF EXISTS public.#{state_type};"
    ])
  end

  @doc """
  Returns the SQL defining a tag-guarded operator over the type.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  * `operator` is `:add`, `:subtract` or `:negate`. `:negate` defines a
    unary `-`; the others define the binary `+` and `-`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.define_operator(spec, :add) =~ "CREATE OPERATOR + ("
      true

  """
  @spec define_operator(TaggedDecimal.t(), :add | :subtract | :negate) :: String.t()
  def define_operator(%TaggedDecimal{} = spec, operator)
      when operator in [:add, :subtract, :negate] do
    function = TaggedDecimal.function_name(spec, operator)

    case operator do
      :negate ->
        join([negate_function(spec, function), negate_operator(spec, function)])

      operator ->
        join([
          binary_operator_function(spec, operator, function),
          binary_operator(spec, operator, function)
        ])
    end
  end

  @doc """
  Returns the SQL dropping an operator over the type and its function.

  ### Arguments

  * `spec` is a `t:Localize.Ecto.TaggedDecimal.t/0`.

  * `operator` is `:add`, `:subtract` or `:negate`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.DDL.drop_operator(spec, :negate)
      "DROP OPERATOR IF EXISTS - (NONE, cldr_unit);\\n\\n\\nDROP FUNCTION IF EXISTS unit_negate(cldr_unit);"

  """
  @spec drop_operator(TaggedDecimal.t(), :add | :subtract | :negate) :: String.t()
  def drop_operator(%TaggedDecimal{} = spec, operator)
      when operator in [:add, :subtract, :negate] do
    symbol = operator_symbol(operator)

    arguments =
      if operator == :negate do
        "NONE, #{spec.type_name}"
      else
        "#{spec.type_name}, #{spec.type_name}"
      end

    argument_types =
      if operator == :negate, do: [spec.type_name], else: [spec.type_name, spec.type_name]

    join([
      "DROP OPERATOR IF EXISTS #{symbol} (#{arguments});",
      drop_function(spec, operator, argument_types)
    ])
  end

  @doc """
  Wraps SQL as a single `execute` call for an Ecto migration.

  ### Arguments

  * `sql` is a SQL string.

  * `append` is a string appended inside the generated `execute` call,
    such as a pipe into a migration-time adjustment. The default is `""`.

  ### Returns

  * The `execute` call as a string.

  ### Examples

      iex> Localize.Ecto.TaggedDecimal.DDL.execute("DROP TYPE public.cldr_unit;")
      "execute \\"DROP TYPE public.cldr_unit;\\""

  """
  @spec execute(String.t(), String.t()) :: String.t()
  def execute(sql, append \\ "") do
    sql = String.trim_trailing(sql, "\n")
    append = if append == "", do: "", else: " " <> append

    if String.contains?(sql, "\n") do
      "execute \"\"\"\n" <> sql <> "\n\"\"\"" <> append
    else
      "execute " <> inspect(sql) <> append
    end
  end

  @doc """
  Wraps each statement of `sql` as its own `execute` call.

  Statements are separated by two blank lines, as the generating
  functions of this module emit them.

  ### Arguments

  * `sql` is a SQL string possibly containing several statements.

  * `append` is a string appended inside each generated `execute` call.
    The default is `""`.

  ### Returns

  * The `execute` calls as a string, one per statement.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit", tag_field: "unit", value_field: "value",
      ...>   function_prefix: "unit", tag_description: "unit name"
      ...> )
      iex> sql = Localize.Ecto.TaggedDecimal.DDL.drop_sum_function(spec)
      iex> Localize.Ecto.TaggedDecimal.DDL.execute_each(sql) |> String.split("\\n") |> length()
      3

  """
  @spec execute_each(String.t(), String.t()) :: String.t()
  def execute_each(sql, append \\ "") do
    sql
    |> String.split(@statement_separator)
    |> Enum.map_join("\n", &execute(&1, append))
  end

  # The state function seeds the accumulated tag from the first non-null
  # row and then guards every subsequent row against it. STRICT means
  # PostgreSQL skips null inputs for us, so the null branch is only ever
  # the initial empty state.
  defp sum_state_function(spec, function_name) do
    argument = spec.argument_name
    extra = extra_declarations(spec)
    extra_assignments = extra_assignments(spec, argument)

    """
    CREATE OR REPLACE FUNCTION #{function_name}(agg_state #{spec.type_name}, #{argument} #{spec.type_name})
    RETURNS #{spec.type_name}
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_tag #{spec.tag_sql_type};
        aggregate #{spec.value_sql_type};
        addition #{spec.value_sql_type};#{extra}
      BEGIN
        IF #{spec.tag_field}(agg_state) IS NULL THEN
          expected_tag := #{spec.tag_field}(#{argument});
          aggregate := 0;
        ELSE
          expected_tag := #{spec.tag_field}(agg_state);
          aggregate := #{spec.value_field}(agg_state);
        END IF;#{extra_assignments}

        IF #{spec.tag_field}(#{argument}) = expected_tag THEN
          addition := aggregate + #{spec.value_field}(#{argument});
          RETURN row(#{row_values(spec, "expected_tag", "addition")});
        ELSE
          #{raise_mismatch(spec, "expected_tag")}
        END IF;
      END;
    $$;
    """
  end

  # Merges two partial aggregations, which is what lets PostgreSQL run
  # the aggregate in parallel workers. Both states are already
  # tag-guarded, so only the two states' tags need comparing.
  defp sum_combine_function(spec, function_name) do
    extra = extra_declarations(spec)

    """
    CREATE OR REPLACE FUNCTION #{function_name}(agg_state1 #{spec.type_name}, agg_state2 #{spec.type_name})
    RETURNS #{spec.type_name}
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_tag #{spec.tag_sql_type};#{extra}
      BEGIN
        expected_tag := #{spec.tag_field}(agg_state1);#{extra_assignments(spec, "agg_state1")}

        IF expected_tag = #{spec.tag_field}(agg_state2) THEN
          RETURN row(#{row_values(spec, "expected_tag", "#{spec.value_field}(agg_state1) + #{spec.value_field}(agg_state2)")});
        ELSE
          #{raise_mismatch(spec, "expected_tag")}
        END IF;
      END;
    $$;
    """
  end

  # `min` and `max` differ only in the comparison, so one template
  # serves both. The state is seeded from the first row by PostgreSQL
  # itself: a STRICT state function with no initial condition is not
  # called until there is a non-null state, which is why the extremum
  # never has to be seeded with a sentinel value.
  defp extremum_statements(spec, {extremum, comparison}) do
    state_function = TaggedDecimal.function_name(spec, :"#{extremum}_state")
    combine_function = TaggedDecimal.function_name(spec, :"#{extremum}_combine")
    argument = spec.argument_name
    extra = extra_declarations(spec)

    [
      """
      CREATE OR REPLACE FUNCTION #{state_function}(agg_state #{spec.type_name}, #{argument} #{spec.type_name})
      RETURNS #{spec.type_name}
      IMMUTABLE
      STRICT
      LANGUAGE plpgsql
      AS $$
        DECLARE
          expected_tag #{spec.tag_sql_type};
          result #{spec.value_sql_type};#{extra}
        BEGIN
          expected_tag := #{spec.tag_field}(agg_state);#{extra_assignments(spec, "agg_state")}

          IF #{spec.tag_field}(#{argument}) = expected_tag THEN
            IF #{spec.value_field}(#{argument}) #{comparison} #{spec.value_field}(agg_state) THEN
              result := #{spec.value_field}(#{argument});
            ELSE
              result := #{spec.value_field}(agg_state);
            END IF;

            RETURN row(#{row_values(spec, "expected_tag", "result")});
          ELSE
            #{raise_mismatch(spec, "expected_tag")}
          END IF;
        END;
      $$;
      """,
      """
      CREATE OR REPLACE FUNCTION #{combine_function}(agg_state1 #{spec.type_name}, agg_state2 #{spec.type_name})
      RETURNS #{spec.type_name}
      IMMUTABLE
      STRICT
      LANGUAGE plpgsql
      AS $$
        DECLARE
          expected_tag #{spec.tag_sql_type};
          result #{spec.value_sql_type};#{extra}
        BEGIN
          expected_tag := #{spec.tag_field}(agg_state1);#{extra_assignments(spec, "agg_state1")}

          IF expected_tag = #{spec.tag_field}(agg_state2) THEN
            IF #{spec.value_field}(agg_state1) #{comparison} #{spec.value_field}(agg_state2) THEN
              result := #{spec.value_field}(agg_state1);
            ELSE
              result := #{spec.value_field}(agg_state2);
            END IF;

            RETURN row(#{row_values(spec, "expected_tag", "result")});
          ELSE
            #{raise_mismatch(spec, "expected_tag")}
          END IF;
        END;
      $$;
      """,
      """
      CREATE OR REPLACE AGGREGATE #{extremum}(#{spec.type_name})
      (
        sfunc = #{state_function},
        stype = #{spec.type_name},
        combinefunc = #{combine_function},
        parallel = SAFE
      );
      """
    ]
  end

  # An average cannot be accumulated in the type itself: dividing needs
  # the count as well as the running total, so the aggregate carries an
  # intermediate state and divides once at the end.
  defp avg_state_type(spec, state_type) do
    extra = Enum.map_join(spec.extra_fields, fn {name, type} -> ", #{name} #{type}" end)

    "CREATE TYPE public.#{state_type} AS (#{spec.tag_field} #{spec.tag_sql_type}, sum #{spec.value_sql_type}, count bigint#{extra});"
  end

  defp avg_state_function(spec, state_type, function_name) do
    argument = spec.argument_name
    extra = extra_declarations(spec)

    """
    CREATE OR REPLACE FUNCTION #{function_name}(agg_state #{state_type}, #{argument} #{spec.type_name})
    RETURNS #{state_type}
    IMMUTABLE
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_tag #{spec.tag_sql_type};
        new_sum #{spec.value_sql_type};
        new_count bigint;#{extra}
      BEGIN
        IF agg_state IS NULL OR agg_state.#{spec.tag_field} IS NULL THEN
          expected_tag := #{spec.tag_field}(#{argument});
          new_sum := #{spec.value_field}(#{argument});
          new_count := 1;#{extra_assignments(spec, argument)}
        ELSE
          expected_tag := agg_state.#{spec.tag_field};#{extra_assignments(spec, "agg_state")}

          IF #{spec.tag_field}(#{argument}) = expected_tag THEN
            new_sum := agg_state.sum + #{spec.value_field}(#{argument});
            new_count := agg_state.count + 1;
          ELSE
            #{raise_mismatch(spec, "expected_tag")}
          END IF;
        END IF;

        RETURN row(#{avg_row_values(spec, "expected_tag", "new_sum", "new_count")})::#{state_type};
      END;
    $$;
    """
  end

  defp avg_combine_function(spec, state_type, function_name) do
    """
    CREATE OR REPLACE FUNCTION #{function_name}(agg_state1 #{state_type}, agg_state2 #{state_type})
    RETURNS #{state_type}
    IMMUTABLE
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF agg_state1 IS NULL THEN
          RETURN agg_state2;
        ELSIF agg_state2 IS NULL THEN
          RETURN agg_state1;
        ELSIF agg_state1.#{spec.tag_field} = agg_state2.#{spec.tag_field} THEN
          RETURN row(#{avg_combine_row_values(spec)})::#{state_type};
        ELSE
          #{raise_mismatch(spec, "agg_state1.#{spec.tag_field}")}
        END IF;
      END;
    $$;
    """
  end

  defp avg_final_function(spec, state_type, function_name) do
    extra = Enum.map_join(spec.extra_fields, fn {name, _type} -> ", agg_state.#{name}" end)

    """
    CREATE OR REPLACE FUNCTION #{function_name}(agg_state #{state_type})
    RETURNS #{spec.type_name}
    IMMUTABLE
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF agg_state IS NULL OR agg_state.count = 0 THEN
          RETURN NULL;
        ELSE
          RETURN row(agg_state.#{spec.tag_field}, agg_state.sum / agg_state.count#{extra})::#{spec.type_name};
        END IF;
      END;
    $$;
    """
  end

  defp binary_operator_function(spec, operator, function_name) do
    left = "#{spec.argument_name}_1"
    right = "#{spec.argument_name}_2"
    arithmetic = if operator == :add, do: "+", else: "-"
    extra = extra_declarations(spec)

    """
    CREATE OR REPLACE FUNCTION #{function_name}(#{left} #{spec.type_name}, #{right} #{spec.type_name})
    RETURNS #{spec.type_name}
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_tag #{spec.tag_sql_type};
        result #{spec.value_sql_type};#{extra}
      BEGIN
        expected_tag := #{spec.tag_field}(#{left});#{extra_assignments(spec, left)}

        IF expected_tag = #{spec.tag_field}(#{right}) THEN
          result := #{spec.value_field}(#{left}) #{arithmetic} #{spec.value_field}(#{right});
          RETURN row(#{row_values(spec, "expected_tag", "result")});
        ELSE
          #{raise_operator_mismatch(spec, operator, "expected_tag")}
        END IF;
      END;
    $$;
    """
  end

  defp binary_operator(spec, operator, function_name) do
    symbol = operator_symbol(operator)
    commutator = if operator == :add, do: ",\n    commutator = +", else: ""

    """
    CREATE OPERATOR #{symbol} (
        leftarg = #{spec.type_name},
        rightarg = #{spec.type_name},
        procedure = #{function_name}#{commutator}
    );
    """
  end

  defp negate_function(spec, function_name) do
    argument = spec.argument_name
    extra = extra_declarations(spec)

    """
    CREATE OR REPLACE FUNCTION #{function_name}(#{argument} #{spec.type_name})
    RETURNS #{spec.type_name}
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_tag #{spec.tag_sql_type};
        result #{spec.value_sql_type};#{extra}
      BEGIN
        expected_tag := #{spec.tag_field}(#{argument});#{extra_assignments(spec, argument)}
        result := -#{spec.value_field}(#{argument});

        RETURN row(#{row_values(spec, "expected_tag", "result")});
      END;
    $$;
    """
  end

  defp negate_operator(spec, function_name) do
    """
    CREATE OPERATOR - (
        rightarg = #{spec.type_name},
        procedure = #{function_name}
    );
    """
  end

  defp avg_row_values(spec, tag, sum, count) do
    row_values_with(spec, [tag, sum, count])
  end

  defp avg_combine_row_values(spec) do
    extra =
      Enum.map(spec.extra_fields, fn {name, _type} -> "agg_state1.#{name}" end)

    Enum.join(
      [
        "agg_state1.#{spec.tag_field}",
        "agg_state1.sum + agg_state2.sum",
        "agg_state1.count + agg_state2.count"
      ] ++ extra,
      ", "
    )
  end

  defp row_values_with(spec, leading) do
    Enum.join(leading ++ Enum.map(spec.extra_fields, fn {name, _type} -> name end), ", ")
  end

  defp operator_symbol(:add), do: "+"
  defp operator_symbol(_operator), do: "-"

  defp raise_operator_mismatch(spec, operator, tag_variable) do
    plural = spec.tag_description_plural
    symbol = operator_symbol(operator)

    message =
      "Incompatible #{plural} for #{symbol} operator. Expected both #{plural} to be %"

    hint = "Please ensure both columns have the same #{spec.tag_description}"

    """
    RAISE EXCEPTION
            #{quote_literal(message)}, #{tag_variable}
            USING HINT = #{quote_literal(hint)},
            ERRCODE = #{quote_literal(spec.errcode)};\
    """
  end

  # Extra fields (a unit's `usage`) are carried through the aggregation
  # unchanged: they describe the tag rather than the value, so there is
  # nothing to accumulate.
  defp extra_declarations(%TaggedDecimal{extra_fields: []}) do
    ""
  end

  defp extra_declarations(%TaggedDecimal{extra_fields: extra_fields}) do
    Enum.map_join(extra_fields, fn {name, type} -> "\n    #{name} #{type};" end)
  end

  defp extra_assignments(%TaggedDecimal{extra_fields: []}, _source) do
    ""
  end

  defp extra_assignments(%TaggedDecimal{extra_fields: extra_fields}, source) do
    Enum.map_join(extra_fields, fn {name, _type} -> "\n    #{name} := #{name}(#{source});" end)
  end

  defp row_values(%TaggedDecimal{} = spec, tag, value) do
    row_values_with(spec, [tag, value])
  end

  defp raise_mismatch(spec, tag_variable) do
    """
    RAISE EXCEPTION
            #{quote_literal(spec.mismatch_message)}, #{tag_variable}
            USING HINT = #{quote_literal(spec.mismatch_hint)},
            ERRCODE = #{quote_literal(spec.errcode)};\
    """
  end

  defp drop_function(spec, role, argument_types) do
    arguments = Enum.join(argument_types, ", ")

    "DROP FUNCTION IF EXISTS #{TaggedDecimal.function_name(spec, role)}(#{arguments});"
  end

  defp quote_literal(string) do
    "'" <> String.replace(string, "'", "''") <> "'"
  end

  defp join(statements) do
    Enum.map_join(statements, @statement_separator, &String.trim_trailing(&1, "\n"))
  end
end

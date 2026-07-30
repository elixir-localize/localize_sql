defmodule Localize.Ecto.TaggedDecimal do
  @moduledoc """
  Describes a *tagged decimal* — a value that pairs a tag with a decimal
  amount — for serialization to a SQL database.

  A tagged decimal is the shape shared by a money amount (a currency code
  and an amount), a unit (a unit name and a value), and anything else
  that is meaningless without the label travelling alongside the number.
  Storing the two together in one column keeps them inseparable, and
  lets the database itself refuse to add euros to yen.

  This module holds the *specification* of one such type: the name of
  the composite type, the names of its fields, and the wording of the
  error raised when two tags do not match. `Localize.Ecto.TaggedDecimal.DDL`
  turns a specification into the SQL that creates the composite type,
  its aggregate functions and its operators, and
  `Localize.Ecto.TaggedDecimal.Composite` and
  `Localize.Ecto.TaggedDecimal.Map` use it to load and dump values
  through Ecto.

  The specification exists because the SQL is otherwise identical
  between domains. `ex_money_sql` describes
  `money_with_currency(currency_code, amount)` and `localize_sql`
  describes `cldr_unit(unit, value)`; the generated plpgsql differs only
  in those identifiers and in the error message.

  ### Field naming

  The field names are part of the specification rather than fixed
  because they are already committed to in deployed databases — a
  generated aggregate must name the same fields as the composite type it
  was created against. PostgreSQL's functional notation makes each field
  callable as a function of the composite (`amount(col)` is `(col).amount`),
  which is how the generated SQL and the Ecto query API read fields.

  ### Examples

      iex> Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "money_with_currency",
      ...>   tag_field: "currency_code",
      ...>   value_field: "amount",
      ...>   function_prefix: "money",
      ...>   tag_description: "currency code"
      ...> ).type_name
      "money_with_currency"

  """

  @enforce_keys [:type_name, :tag_field, :value_field, :function_prefix, :tag_description]

  defstruct type_name: nil,
            tag_field: nil,
            value_field: nil,
            function_prefix: nil,
            tag_description: nil,
            tag_sql_type: "varchar",
            value_sql_type: "numeric",
            extra_fields: [],
            argument_name: nil,
            function_names: %{},
            tag_description_plural: nil,
            mismatch_message: nil,
            mismatch_hint: nil,
            errcode: "22033"

  @type sql_identifier :: String.t()

  @type t :: %__MODULE__{
          type_name: sql_identifier(),
          tag_field: sql_identifier(),
          value_field: sql_identifier(),
          function_prefix: sql_identifier(),
          tag_description: String.t(),
          tag_sql_type: String.t(),
          value_sql_type: String.t(),
          extra_fields: [{sql_identifier(), String.t()}],
          argument_name: sql_identifier(),
          function_names: %{atom() => sql_identifier()},
          tag_description_plural: String.t(),
          mismatch_message: String.t(),
          mismatch_hint: String.t(),
          errcode: String.t()
        }

  @doc """
  Returns a tagged decimal specification.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:type_name` is the name of the SQL composite type, such as
    `"money_with_currency"`. Required.

  * `:tag_field` is the name of the composite field holding the tag, such
    as `"currency_code"`. Required.

  * `:value_field` is the name of the composite field holding the decimal,
    such as `"amount"`. Required.

  * `:function_prefix` is the prefix given to generated function names,
    such as `"money"` for `money_sum_state_function`. Required.

  * `:tag_description` is the human-readable name of the tag used in
    error messages, such as `"currency code"`. Required.

  * `:tag_sql_type` is the SQL type of the tag field. The default is
    `"varchar"`.

  * `:value_sql_type` is the SQL type of the value field. The default is
    `"numeric"`.

  * `:extra_fields` is a list of `{name, sql_type}` tuples appended to
    the composite type after the tag and value, such as
    `[{"usage", "varchar"}]`. The default is `[]`.

  * `:argument_name` is the name given to the incoming row in generated
    plpgsql. The default is the `:function_prefix`.

  * `:function_names` is a map of overrides for generated function
    names, keyed by `:sum_state`, `:sum_combine`, `:avg_state`,
    `:avg_combine`, `:avg_final`, `:avg_state_type`, `:min_state`,
    `:min_combine`, `:max_state`, `:max_combine`, `:add`, `:subtract`
    and `:negate`. The `:avg_state_type` key names the intermediate
    composite type the `avg` aggregate accumulates into rather than a
    function.
    Deployed databases name these functions in their aggregate
    definitions, so an existing name that does not follow the default
    pattern is preserved here. The default is `%{}`.

  * `:tag_description_plural` is the plural of `:tag_description`, used
    in generated error messages. The default appends `"s"`.

  * `:mismatch_message` is the message of the exception raised when two
    tags differ. The default is derived from `:tag_description`.

  * `:mismatch_hint` is the hint attached to that exception. The default
    is derived from `:tag_description`.

  * `:errcode` is the SQLSTATE raised on a tag mismatch. The default is
    `"22033"`, which is the code the aggregates of `ex_money_sql` and
    `localize_units_sql` have always raised and is therefore what
    deployed functions and any consumer rescuing them already use. Note
    that `22033` is `invalid_sql_json_subscript` in PostgreSQL 16 and
    later, not the `invalid_parameter_value` (`22023`) the wording of
    these messages suggests — pass `:errcode` explicitly to choose a
    different code for a new type.

  ### Returns

  * `{:ok, spec}` where `spec` is a `t:t/0`, or

  * `{:error, exception}` if a required option is missing or an option
    has an invalid value.

  ### Examples

      iex> {:ok, spec} = Localize.Ecto.TaggedDecimal.new(
      ...>   type_name: "cldr_unit",
      ...>   tag_field: "unit",
      ...>   value_field: "value",
      ...>   function_prefix: "unit",
      ...>   tag_description: "unit name"
      ...> )
      iex> spec.mismatch_message
      "Incompatible unit names. Expected all unit names to be %"

      iex> {:error, exception} = Localize.Ecto.TaggedDecimal.new(tag_field: "unit")
      iex> is_exception(exception)
      true

  """
  @spec new(Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(options) do
    with {:ok, options} <- validate_required(options),
         {:ok, options} <- validate_extra_fields(options) do
      {:ok, struct!(__MODULE__, apply_defaults(options))}
    end
  end

  @doc """
  Returns a tagged decimal specification or raises.

  ### Arguments

  * `options` is a keyword list of options. See `new/1`.

  ### Returns

  * A `t:t/0`, or

  * raises if an option is missing or invalid.

  ### Examples

      iex> Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit",
      ...>   tag_field: "unit",
      ...>   value_field: "value",
      ...>   function_prefix: "unit",
      ...>   tag_description: "unit name"
      ...> ).tag_field
      "unit"

  """
  @spec new!(Keyword.t()) :: t() | no_return()
  def new!(options) do
    case new(options) do
      {:ok, spec} -> spec
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the name of a generated function for a specification.

  Names follow `<function_prefix>_<role>_function` — for example
  `money_sum_state_function` — unless overridden by the
  `:function_names` option of `new/1`.

  ### Arguments

  * `spec` is a `t:t/0`.

  * `role` is one of `:sum_state`, `:sum_combine`, `:avg_state`,
    `:avg_combine`, `:avg_final`, `:min_state`, `:min_combine`,
    `:max_state`, `:max_combine`, `:add`, `:subtract` or `:negate`.

  ### Returns

  * The function name as a string.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "money_with_currency", tag_field: "currency_code",
      ...>   value_field: "amount", function_prefix: "money",
      ...>   tag_description: "currency code"
      ...> )
      iex> Localize.Ecto.TaggedDecimal.function_name(spec, :sum_state)
      "money_sum_state_function"
      iex> Localize.Ecto.TaggedDecimal.function_name(spec, :add)
      "money_add"

  """
  @spec function_name(t(), atom()) :: sql_identifier()
  def function_name(%__MODULE__{} = spec, role) do
    case Map.fetch(spec.function_names, role) do
      {:ok, name} -> name
      :error -> default_function_name(spec, role)
    end
  end

  @doc """
  Returns the fields of the composite type as `{name, sql_type}` tuples.

  The tag and value fields come first, in that order, followed by any
  `:extra_fields`.

  ### Arguments

  * `spec` is a `t:t/0`.

  ### Returns

  * A list of `{name, sql_type}` tuples.

  ### Examples

      iex> spec = Localize.Ecto.TaggedDecimal.new!(
      ...>   type_name: "cldr_unit_with_usage", tag_field: "unit",
      ...>   value_field: "value", function_prefix: "unit_with_usage",
      ...>   tag_description: "unit name", extra_fields: [{"usage", "varchar"}]
      ...> )
      iex> Localize.Ecto.TaggedDecimal.fields(spec)
      [{"unit", "varchar"}, {"value", "numeric"}, {"usage", "varchar"}]

  """
  @spec fields(t()) :: [{sql_identifier(), String.t()}]
  def fields(%__MODULE__{} = spec) do
    [{spec.tag_field, spec.tag_sql_type}, {spec.value_field, spec.value_sql_type}] ++
      spec.extra_fields
  end

  defp validate_required(options) do
    missing = Enum.reject(@enforce_keys, &Keyword.has_key?(options, &1))

    if missing == [] do
      {:ok, options}
    else
      {:error,
       ArgumentError.exception(
         "missing required options for a tagged decimal specification: " <>
           Enum.map_join(missing, ", ", &inspect/1)
       )}
    end
  end

  defp validate_extra_fields(options) do
    extra_fields = Keyword.get(options, :extra_fields, [])

    if is_list(extra_fields) and
         Enum.all?(
           extra_fields,
           &match?({name, type} when is_binary(name) and is_binary(type), &1)
         ) do
      {:ok, options}
    else
      {:error,
       ArgumentError.exception(
         ":extra_fields must be a list of {name, sql_type} string tuples, found " <>
           inspect(extra_fields)
       )}
    end
  end

  defp apply_defaults(options) do
    tag_description = Keyword.fetch!(options, :tag_description)

    options =
      Keyword.put_new_lazy(options, :tag_description_plural, fn -> pluralize(tag_description) end)

    plural = Keyword.fetch!(options, :tag_description_plural)

    options
    |> Keyword.put_new(:argument_name, Keyword.fetch!(options, :function_prefix))
    |> Keyword.put_new_lazy(:mismatch_message, fn ->
      "Incompatible #{plural}. Expected all #{plural} to be %"
    end)
    |> Keyword.put_new_lazy(:mismatch_hint, fn ->
      "Please ensure all columns have the same #{tag_description}"
    end)
  end

  # The generated names are `<prefix>_<aggregate>_<role>_function` for
  # the aggregate support functions and `<prefix>_<operation>` for the
  # operator functions, matching the names ex_money_sql established.
  defp default_function_name(spec, role) do
    case role do
      :avg_state_type -> "#{spec.function_prefix}_avg_state"
      :add -> "#{spec.function_prefix}_add"
      :subtract -> "#{spec.function_prefix}_sub"
      :negate -> "#{spec.function_prefix}_negate"
      role -> "#{spec.function_prefix}_#{role}_function"
    end
  end

  defp pluralize(tag_description) do
    if String.ends_with?(tag_description, "s") do
      tag_description
    else
      tag_description <> "s"
    end
  end
end

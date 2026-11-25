defmodule Localize.Message.Ecto.Type do
  @moduledoc """
  An `Ecto.Type` storing an MF2 message, validated when it is written, in a text column.

  A message an application keeps as data, such as a translation a site's editors write, is checked when it is cast and when it is dumped: it must be valid MF2 syntax and satisfy TR35's data-model rules, so a `.match` with no `*` variant or a variable declared twice is refused by the changeset rather than found when a visitor's page renders.

  The value is the message's source as written, a string, so a form shows and edits it as it is. To format it many times, parse it once with `Localize.Message.parse/2` and format the result.

  ### Schema

      # in a migration
      add :greeting, :text

      # in a schema
      field :greeting, Localize.Message.Ecto.Type

  ### Casting

  `cast/1` accepts a message string or a `t:Localize.Message.Parsed.t/0`, whose source is taken. A message that is not valid returns the error `"is not a valid MF2 message: %{detail}"`, with what is wrong in `:detail`. The message is a fixed msgid, so an application's `translate_error/1` can translate it, with `detail` as a binding.

  ### Loading

  `load/1` returns the stored text as it is, without validating it, since Ecto raises when a value cannot be loaded and a row written before the column held validated messages must still be readable. Validate a loaded message with `Localize.Message.parse/2` where that matters.

  """

  use Ecto.Type

  alias Localize.Message.Parsed

  @invalid_message "is not a valid MF2 message: %{detail}"

  @impl Ecto.Type
  def type do
    :string
  end

  @impl Ecto.Type
  def cast(nil) do
    {:ok, nil}
  end

  def cast(%Parsed{source: source}) do
    {:ok, source}
  end

  def cast(message) when is_binary(message) do
    case Localize.Message.parse(message) do
      {:ok, _parsed} ->
        {:ok, message}

      {:error, exception} ->
        {:error, message: @invalid_message, detail: Exception.message(exception)}
    end
  end

  def cast(_message) do
    :error
  end

  @impl Ecto.Type
  def load(nil) do
    {:ok, nil}
  end

  def load(message) when is_binary(message) do
    {:ok, message}
  end

  def load(_message) do
    :error
  end

  @impl Ecto.Type
  def dump(nil) do
    {:ok, nil}
  end

  def dump(%Parsed{source: source}) do
    {:ok, source}
  end

  def dump(message) when is_binary(message) do
    case Localize.Message.parse(message) do
      {:ok, _parsed} -> {:ok, message}
      {:error, _exception} -> :error
    end
  end

  def dump(_message) do
    :error
  end
end

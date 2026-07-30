defmodule Localize.LanguageTag.Ecto.Type do
  @moduledoc """
  An `Ecto.Type` storing a locale as its BCP 47 string in a text column.

  A `t:Localize.LanguageTag.t/0` is a rich struct — resolved likely
  subtags, `-u-` extension keywords, a canonical form — but all of it is
  derived from the language tag string, so the string is what is stored.
  The column is ordinary text holding a canonical tag such as `"en-US"`
  or `"de-DE-u-co-phonebk"`.

  Values load back into a fully resolved `t:Localize.LanguageTag.t/0` via
  `Localize.validate_locale/1`, so a loaded locale is canonicalized, has
  its `-u-` extensions populated and its likely subtags resolved — the
  same value `Localize.validate_locale/1` returns anywhere else, and the
  resolution is cached.

  ### Schema

      # in a migration
      add :locale, :string

      # in a schema
      field :locale, Localize.LanguageTag.Ecto.Type

  ### Casting

  `cast/1` accepts a `t:Localize.LanguageTag.t/0`, or any locale
  identifier `Localize.validate_locale/1` accepts — a string (`"en-US"`)
  or an atom (`:"en-US"`). An identifier that is not a valid locale
  returns an error rather than being stored.

  """

  use Ecto.Type

  alias Localize.LanguageTag

  @impl Ecto.Type
  def type do
    :string
  end

  @impl Ecto.Type
  def cast(nil) do
    {:ok, nil}
  end

  def cast(%LanguageTag{} = language_tag) do
    {:ok, language_tag}
  end

  def cast(locale) when is_binary(locale) or is_atom(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> {:ok, language_tag}
      {:error, exception} -> {:error, message: Exception.message(exception)}
    end
  end

  def cast(_locale) do
    :error
  end

  @impl Ecto.Type
  def load(nil) do
    {:ok, nil}
  end

  def load(locale) when is_binary(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> {:ok, language_tag}
      {:error, _exception} -> :error
    end
  end

  def load(_locale) do
    :error
  end

  @impl Ecto.Type
  def dump(nil) do
    {:ok, nil}
  end

  def dump(%LanguageTag{} = language_tag) do
    {:ok, LanguageTag.to_string(language_tag)}
  end

  def dump(locale) when is_binary(locale) or is_atom(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> dump(language_tag)
      {:error, _exception} -> :error
    end
  end

  def dump(_locale) do
    :error
  end
end

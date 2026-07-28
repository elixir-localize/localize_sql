defmodule Localize.Ecto.DocumentationTest do
  # The README and the Audit docs show sample output containing the
  # CLDR version, which comes from the localize dependency and moves
  # with it. Twice now that has gone stale unnoticed between releases,
  # so it is asserted rather than reviewed by eye.
  use ExUnit.Case, async: true

  @cldr_version to_string(Localize.version())

  test "the CLDR version in the README sample output is current" do
    readme = File.read!(Path.join(__DIR__, "../../../README.md"))

    assert readme =~ "Application: CLDR #{@cldr_version},",
           """
           README.md shows a stale CLDR version in the `mix localize.ecto.audit` \
           sample output. localize now reports #{@cldr_version}.
           """
  end

  test "the CLDR version in the Audit docs is current" do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(Localize.Ecto.Audit)

    {_, _, _, %{"en" => doc}, _} =
      Enum.find(docs, fn {{_kind, name, arity}, _, _, _, _} ->
        {name, arity} == {:unicode_versions, 1}
      end)

    assert doc =~ ~s|cldr: "#{@cldr_version}"|,
           """
           The unicode_versions/1 example in lib/localize/ecto/audit.ex shows a \
           stale CLDR version. localize now reports #{@cldr_version}.
           """
  end
end

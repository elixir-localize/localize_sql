defmodule Localize.Ecto.Migration.GeneratorTest do
  use ExUnit.Case, async: true

  alias Localize.Ecto.Migration.Generator
  alias Localize.Unit.DDL

  doctest Localize.Ecto.Migration.Generator

  describe "render/3" do
    test "produces a compilable migration from the unit DDL" do
      up = DDL.execute_each(DDL.create_cldr_unit())
      down = DDL.execute_each(DDL.drop_cldr_unit())

      source = Generator.render(GeneratorTestRepo.Migrations.AddCldrUnit, up, down)

      assert source =~ "use Ecto.Migration"
      assert source =~ "def up do"
      assert source =~ "def down do"
      assert source =~ "CREATE TYPE public.cldr_unit AS"

      # The embedded SQL and generated module must be valid Elixir. It
      # references Ecto.Migration macros, so it is quoted rather than
      # evaluated — parsing is enough to prove the source is well formed.
      assert {:ok, _ast} = Code.string_to_quoted(source)
    end

    test "is already formatted and newline terminated" do
      source =
        Generator.render(
          MyApp.Repo.Migrations.AddCldrUnit,
          ~s|execute "CREATE TYPE public.cldr_unit AS (unit varchar, value numeric);"|,
          ~s|execute "DROP TYPE public.cldr_unit;"|
        )

      assert String.ends_with?(source, "end\n")
      assert source == IO.iodata_to_binary(Code.format_string!(source)) <> "\n"
    end
  end

  describe "timestamp/0" do
    test "is fourteen digits" do
      assert Generator.timestamp() =~ ~r/^\d{14}$/
    end
  end
end

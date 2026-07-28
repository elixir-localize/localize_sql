defmodule Localize.Ecto.SQLite3.IntegrationTest do
  # Exercises the macros end to end through a real ecto_sqlite3 repo
  # with the extension loaded by :load_extensions, which is how an
  # application wires it up.
  use ExUnit.Case, async: false

  import Ecto.Query
  import Localize.Ecto.SQLite3

  @moduletag :sqlite_icu

  alias Localize.Ecto.SQLiteTestRepo, as: Repo

  setup_all do
    Repo.query!("CREATE TABLE IF NOT EXISTS words (id INTEGER PRIMARY KEY, word TEXT)")
    Repo.query!("DELETE FROM words")

    for word <- ["Muller", "Müller", "Mueller", "Mahler"] do
      Repo.query!("INSERT INTO words (word) VALUES (?)", [word])
    end

    :ok
  end

  defp words_ordered_by(locale_or_options) do
    Repo.all(from w in "words", order_by: collate(w.word, ^locale_or_options), select: w.word)
  end

  describe "collate/2" do
    test "orders by the collation of the locale" do
      assert words_ordered_by("de") == ["Mahler", "Mueller", "Muller", "Müller"]
    end

    test "a BCP 47 collation type needs no migration, unlike PostgreSQL" do
      assert words_ordered_by("de-u-co-phonebk") == ["Mahler", "Mueller", "Müller", "Muller"]
    end

    test "an unrelated locale still resolves through language matching" do
      assert words_ordered_by("de-AT") == ["Mahler", "Mueller", "Muller", "Müller"]
    end

    test "collates a comparison in a where clause" do
      query =
        from w in "words",
          where: collate(w.word < "Muller", "de"),
          select: w.word,
          order_by: w.word

      assert Repo.all(query) == ["Mahler", "Mueller"]
    end
  end

  describe "case mapping" do
    test "lower/2 and upper/2 follow the locale" do
      assert Repo.one(from w in "words", where: w.word == "Mahler", select: upper(w.word, "tr")) ==
               "MAHLER"

      assert Repo.one(from w in "words", where: w.word == "Mahler", select: lower(w.word, "tr")) ==
               "mahler"
    end

    test "Turkish case mapping differs from the default" do
      turkish = Repo.one(from w in "words", limit: 1, select: upper(^"i", "tr"))
      english = Repo.one(from w in "words", limit: 1, select: upper(^"i", "en"))

      assert turkish == "İ"
      assert english == "I"
    end

    test "initcap/2 title-cases" do
      assert Repo.one(from w in "words", limit: 1, select: initcap(^"von neumann", "en")) ==
               "Von Neumann"
    end
  end

  describe "indexes" do
    test "a collated unique index enforces case-insensitive uniqueness" do
      Repo.query!("CREATE TABLE IF NOT EXISTS accounts (email TEXT)")
      Repo.query!("DELETE FROM accounts")

      Repo.query!("""
      CREATE UNIQUE INDEX IF NOT EXISTS accounts_email
      ON accounts (#{Localize.Ecto.Migration.collated(:email, "und-u-ks-level1")})
      """)

      Repo.query!("INSERT INTO accounts (email) VALUES (?)", ["Ann@Example.com"])

      assert {:error, error} =
               Repo.query("INSERT INTO accounts (email) VALUES (?)", ["ann@example.com"])

      assert Exception.message(error) =~ "UNIQUE constraint failed"
    end
  end
end

defmodule Localize.Ecto.SQLite3.ExtensionTest do
  # Drives the localize_icu extension through Exqlite directly, without
  # Ecto in the way, so a failure here is a failure of the extension.
  use ExUnit.Case, async: true

  @moduletag :sqlite_icu

  alias Exqlite.Sqlite3
  alias Localize.Ecto.SQLite3.Extension

  setup do
    {:ok, db} = Sqlite3.open(":memory:")
    :ok = Sqlite3.enable_load_extension(db, true)
    :ok = Sqlite3.execute(db, "SELECT load_extension('#{Extension.path()}')")
    :ok = Sqlite3.enable_load_extension(db, false)

    on_exit(fn -> Sqlite3.close(db) end)

    {:ok, db: db}
  end

  defp query(db, sql) do
    {:ok, statement} = Sqlite3.prepare(db, sql)
    {:ok, rows} = Sqlite3.fetch_all(db, statement)
    :ok = Sqlite3.release(db, statement)
    rows
  end

  defp sorted(db, words, collation) do
    values = Enum.map_join(words, ",", &"('#{&1}')")

    db
    |> query("""
    SELECT word FROM (SELECT column1 AS word FROM (VALUES #{values}))
    ORDER BY word COLLATE "#{collation}"
    """)
    |> List.flatten()
  end

  describe "collation registration" do
    test "registers a collation on first use without any migration", %{db: db} do
      assert sorted(db, ~w(zebra apple ost), "de-x-icu") == ~w(apple ost zebra)
    end

    test "accepts a bare language tag as well as a PostgreSQL -x-icu name", %{db: db} do
      assert sorted(db, ~w(zebra apple), "de") == sorted(db, ~w(zebra apple), "de-x-icu")
    end

    test "matches collation names case insensitively, as SQLite does", %{db: db} do
      assert sorted(db, ~w(zebra apple), "DE-X-ICU") == ~w(apple zebra)
    end

    test "und-x-icu resolves to the root collation", %{db: db} do
      assert sorted(db, ~w(Z a), "und-x-icu") == ~w(a Z)
    end

    test "a script and territory qualified name resolves", %{db: db} do
      assert sorted(db, ~w(b a), "zh-Hant-TW-x-icu") == ~w(a b)
    end

    test "an unregistrable name leaves SQLite to report it", %{db: db} do
      assert {:error, message} = Sqlite3.prepare(db, ~s|SELECT 1 = 2 COLLATE "not a tag!!"|)
      assert message =~ "no such collation sequence"
    end
  end

  describe "language-specific ordering" do
    # Swedish sorts ä after z; German sorts it with a. Getting both
    # right from the same data is the point of the exercise.
    test "German and Swedish disagree about ä, as they should", %{db: db} do
      words = ~w(zebra äpple apple ost)

      assert sorted(db, words, "de-x-icu") == ~w(apple äpple ost zebra)
      assert sorted(db, words, "sv-x-icu") == ~w(apple ost zebra äpple)
    end
  end

  describe "BCP 47 -u- tailorings" do
    # PostgreSQL needs CREATE COLLATION for each of these. SQLite builds
    # them on demand, so they work with no setup at all.
    test "-u-co-phonebk sorts ü as ue where the standard collation does not", %{db: db} do
      words = ~w(Mahler Muller Müller Mueller)

      assert sorted(db, words, "de-x-icu") == ~w(Mahler Mueller Muller Müller)
      assert sorted(db, words, "de-u-co-phonebk-x-icu") == ~w(Mahler Mueller Müller Muller)
    end

    test "-u-kn-true sorts digit runs numerically", %{db: db} do
      words = ~w(file10 file2 file1)

      assert sorted(db, words, "en-x-icu") == ~w(file1 file10 file2)
      assert sorted(db, words, "en-u-kn-true-x-icu") == ~w(file1 file2 file10)
    end

    test "-u-ks-level1 compares case and accent insensitively", %{db: db} do
      assert query(db, ~s|SELECT 'a' = 'A' COLLATE "und-u-ks-level1-x-icu"|) == [[1]]
      assert query(db, ~s|SELECT 'a' = 'A' COLLATE "und-x-icu"|) == [[0]]
      assert query(db, ~s|SELECT 'resume' = 'résumé' COLLATE "und-u-ks-level1-x-icu"|) == [[1]]
    end

    test "-u-ks-level2 ignores case but not accents", %{db: db} do
      assert query(db, ~s|SELECT 'a' = 'A' COLLATE "und-u-ks-level2-x-icu"|) == [[1]]
      assert query(db, ~s|SELECT 'resume' = 'résumé' COLLATE "und-u-ks-level2-x-icu"|) == [[0]]
    end

    test "a primary-strength collation makes a unique index case insensitive", %{db: db} do
      :ok = Sqlite3.execute(db, "CREATE TABLE users (email TEXT)")

      :ok =
        Sqlite3.execute(
          db,
          ~s|CREATE UNIQUE INDEX users_email ON users (email COLLATE "und-u-ks-level1-x-icu")|
        )

      :ok = Sqlite3.execute(db, "INSERT INTO users VALUES ('Ann@Example.com')")

      assert {:error, message} =
               Sqlite3.execute(db, "INSERT INTO users VALUES ('ann@example.com')")

      assert message =~ "UNIQUE constraint failed"
    end
  end

  describe "ICU case mapping" do
    test "upper/2 and lower/2 follow the locale", %{db: db} do
      assert query(db, "SELECT upper('i', 'tr'), upper('i', 'en')") == [["İ", "I"]]
      assert query(db, "SELECT lower('I', 'tr'), lower('I', 'en')") == [["ı", "i"]]
    end

    test "case mapping handles growth, as ß to SS", %{db: db} do
      assert query(db, "SELECT upper('straße', 'de')") == [["STRASSE"]]
    end

    test "title/2 title-cases each word", %{db: db} do
      assert query(db, "SELECT title('von neumann', 'en')") == [["Von Neumann"]]
    end

    test "the locale accepts a collation name as well as a bare tag", %{db: db} do
      assert query(db, "SELECT upper('i', 'tr-x-icu')") == [["İ"]]
    end

    test "a NULL input yields NULL, as SQLite's own upper does", %{db: db} do
      assert query(db, "SELECT upper(NULL, 'en')") == [[nil]]
    end

    test "the one-argument builtins are left alone", %{db: db} do
      # SQLite's builtin upper/1 is ASCII only; if the extension had
      # overridden it this would come back uppercased.
      assert query(db, "SELECT upper('é')") == [["é"]]
    end

    test "an unrecognized locale is an error", %{db: db} do
      assert {:error, message} = Sqlite3.execute(db, "SELECT upper('x', 'not a tag!!')")
      assert message =~ "unrecognized locale"
    end
  end
end

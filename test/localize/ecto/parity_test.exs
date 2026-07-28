defmodule Localize.Ecto.ParityTest do
  @moduledoc false

  # The compatibility proof: the same word list, ordered by PostgreSQL
  # and by SQLite under the collation name the same locale resolves to,
  # must come back in the same order.
  #
  # Both sides reach ICU the same way — uloc_forLanguageTag() then
  # ucol_open() — so agreement is expected as long as the two link
  # comparable ICU versions. A failure here is either a real defect or
  # ICU version skew between the PostgreSQL server and the extension;
  # the failure message reports the collation so the two can be
  # compared with pg_collation.collversion.
  use ExUnit.Case, async: false

  import Ecto.Query

  @moduletag :sqlite_icu

  require Localize.Ecto.Postgres
  require Localize.Ecto.SQLite3

  alias Localize.Ecto.SQLiteTestRepo
  alias Localize.Ecto.TestRepo

  @words [
    "Mahler",
    "Muller",
    "Müller",
    "Mueller",
    "apple",
    "äpple",
    "ost",
    "zebra",
    "Zebra",
    "cafe",
    "café",
    "Café",
    "strasse",
    "straße",
    "file2",
    "file10",
    "angstrom",
    "Ångström",
    "łódź",
    "lodz",
    "çilek",
    "cilek"
  ]

  # Plain locales are preloaded by initdb on the PostgreSQL side; the
  # tailored ones have to be created there first, which is exactly the
  # asymmetry the SQLite extension removes.
  @plain_locales ["und", "en", "de", "sv", "fr", "es", "tr", "da", "pl", "cs", "zh-TW"]
  @tailored_locales ["de-u-co-phonebk", "en-u-kn-true", "und-u-ks-level1"]

  setup_all do
    TestRepo.query!("CREATE TABLE IF NOT EXISTS parity_words (word text)")
    TestRepo.query!("TRUNCATE parity_words")

    SQLiteTestRepo.query!("CREATE TABLE IF NOT EXISTS parity_words (word TEXT)")
    SQLiteTestRepo.query!("DELETE FROM parity_words")

    for word <- @words do
      TestRepo.query!("INSERT INTO parity_words (word) VALUES ($1)", [word])
      SQLiteTestRepo.query!("INSERT INTO parity_words (word) VALUES (?)", [word])
    end

    for locale <- @tailored_locales do
      TestRepo.query!(Localize.Ecto.Migration.create_collation_sql(locale, if_not_exists: true))
    end

    :ok
  end

  # A secondary sort under the root collation breaks ties, so that a
  # strength-reduced collation (which deliberately makes words compare
  # equal) still yields one total order on both databases.
  defp postgres_order(locale) do
    TestRepo.all(
      from w in "parity_words",
        order_by: [
          Localize.Ecto.Postgres.collate(w.word, ^locale),
          Localize.Ecto.Postgres.collate(w.word, "und")
        ],
        select: w.word
    )
  end

  defp sqlite_order(locale) do
    SQLiteTestRepo.all(
      from w in "parity_words",
        order_by: [
          Localize.Ecto.SQLite3.collate(w.word, ^locale),
          Localize.Ecto.SQLite3.collate(w.word, "und")
        ],
        select: w.word
    )
  end

  defp assert_parity(locale) do
    collation = Localize.Ecto.Collation.collation_for!(locale)
    postgres = postgres_order(locale)
    sqlite = sqlite_order(locale)

    assert postgres == sqlite,
           """
           PostgreSQL and SQLite disagree for locale #{inspect(locale)} \
           (collation #{inspect(collation)}).

           PostgreSQL: #{inspect(postgres)}
           SQLite:     #{inspect(sqlite)}

           If the orderings differ only in placement of accented or cased \
           forms, compare the ICU versions: \
           SELECT collversion FROM pg_collation WHERE collname = '#{collation}';
           """
  end

  describe "ordering parity for preloaded collations" do
    for locale <- @plain_locales do
      test "#{locale} sorts identically on PostgreSQL and SQLite" do
        assert_parity(unquote(locale))
      end
    end
  end

  describe "ordering parity for BCP 47 tailorings" do
    for locale <- @tailored_locales do
      test "#{locale} sorts identically on PostgreSQL and SQLite" do
        assert_parity(unquote(locale))
      end
    end
  end

  describe "canonical equivalence differs, ordering does not" do
    # The one documented behavioural difference between the two. ICU
    # treats canonically equivalent strings as equal; PostgreSQL's
    # deterministic collations then break the tie bytewise, SQLite has
    # no such concept and reports ICU's answer. Ordering is unaffected,
    # which is why the ordering parity above still holds.
    test "PostgreSQL reports them unequal and SQLite reports them equal" do
      nfc = String.normalize("café", :nfc)
      nfd = String.normalize("café", :nfd)

      postgres =
        TestRepo.query!("SELECT $1::text = $2::text COLLATE \"fr-x-icu\"", [nfc, nfd])

      sqlite = SQLiteTestRepo.query!("SELECT ? = ? COLLATE \"fr-x-icu\"", [nfc, nfd])

      assert postgres.rows == [[false]]
      assert sqlite.rows == [[1]]
    end

    test "both order the two forms adjacently" do
      nfc = String.normalize("café", :nfc)
      nfd = String.normalize("café", :nfd)

      for repo <- [TestRepo, SQLiteTestRepo] do
        repo.query!("CREATE TABLE IF NOT EXISTS norm_words (word text)")
        repo.query!("DELETE FROM norm_words")
      end

      for word <- ["cafz", nfd, nfc, "cafa"] do
        TestRepo.query!("INSERT INTO norm_words (word) VALUES ($1)", [word])
        SQLiteTestRepo.query!("INSERT INTO norm_words (word) VALUES (?)", [word])
      end

      postgres =
        TestRepo.query!(~s|SELECT word FROM norm_words ORDER BY word COLLATE "fr-x-icu"|).rows

      sqlite =
        SQLiteTestRepo.query!(~s|SELECT word FROM norm_words ORDER BY word COLLATE "fr-x-icu"|).rows

      # The two café forms occupy positions 2 and 3 in both, whichever
      # order the tie-break puts them in.
      assert [["cafa"], _, _, ["cafz"]] = postgres
      assert [["cafa"], _, _, ["cafz"]] = sqlite
      assert Enum.sort(postgres) == Enum.sort(sqlite)
    end
  end

  describe "name parity" do
    test "every plain locale resolves to a collation PostgreSQL preloaded" do
      preloaded =
        "SELECT collname FROM pg_collation WHERE collprovider = 'i'"
        |> TestRepo.query!()
        |> Map.fetch!(:rows)
        |> List.flatten()
        |> MapSet.new()

      for locale <- @plain_locales do
        collation = Localize.Ecto.Collation.collation_for!(locale)

        assert MapSet.member?(preloaded, collation),
               "#{locale} resolved to #{collation}, which PostgreSQL did not preload"
      end
    end
  end
end

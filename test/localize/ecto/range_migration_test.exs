defmodule Localize.Ecto.RangeMigrationTest do
  # Runs a real migration, creating database-global objects.
  use ExUnit.Case, async: false

  alias Localize.Ecto.Range.Migration
  alias Localize.Ecto.TestRepo

  doctest Localize.Ecto.Range.Migration

  defmodule BookingsMigration do
    @moduledoc false

    use Ecto.Migration

    import Localize.Ecto.Range.Migration

    def change do
      create_btree_gist()
      create_time_range(name: "test_timerange")

      create table(:range_bookings) do
        add(:room_id, :integer, null: false)
        add(:period, :tstzrange, null: false)
      end

      create(no_overlap(:range_bookings, :period, scope: [:room_id]))
    end
  end

  setup_all do
    # A previous aborted run may have left these behind.
    TestRepo.query("DROP TABLE IF EXISTS range_bookings")
    TestRepo.query("DROP TYPE IF EXISTS test_timerange")

    Ecto.Migrator.up(TestRepo, 20_260_730_000_001, BookingsMigration, log: false)

    on_exit(fn ->
      TestRepo.query("DROP TABLE IF EXISTS range_bookings")
      TestRepo.query("DROP TYPE IF EXISTS test_timerange")
      TestRepo.query("DELETE FROM schema_migrations WHERE version = 20260730000001")
    end)

    :ok
  end

  describe "no_overlap/3" do
    test "builds a gist exclusion constraint over the range column" do
      constraint = Migration.no_overlap(:bookings, :period)

      assert constraint.table == "bookings"
      assert constraint.name == "bookings_period_no_overlap"
      assert constraint.exclude == ~s|gist ("period" WITH &&)|
    end

    test "a scope is compared for equality and precedes the range" do
      constraint = Migration.no_overlap(:bookings, :period, scope: [:room_id])

      assert constraint.exclude == ~s|gist ("room_id" WITH =, "period" WITH &&)|
    end

    test "accepts several scope columns" do
      constraint = Migration.no_overlap(:bookings, :period, scope: [:site_id, :room_id])

      assert constraint.exclude ==
               ~s|gist ("site_id" WITH =, "room_id" WITH =, "period" WITH &&)|
    end

    test "accepts an explicit name and a where predicate" do
      constraint =
        Migration.no_overlap(:bookings, :period,
          name: "one_booking_at_a_time",
          where: "status <> 'cancelled'"
        )

      assert constraint.name == "one_booking_at_a_time"

      assert constraint.exclude ==
               ~s|gist ("period" WITH &&) WHERE (status <> 'cancelled')|
    end
  end

  describe "running the migration" do
    setup do
      TestRepo.query!("TRUNCATE range_bookings")
      :ok
    end

    test "creates the time range type" do
      assert TestRepo.query!("SELECT '[09:00,17:00)'::test_timerange @> '12:30'::time").rows ==
               [[true]]
    end

    test "the time range type spans time of day" do
      assert TestRepo.query!("SELECT lower('[09:00,17:00)'::test_timerange)::text").rows ==
               [["09:00:00"]]
    end

    test "accepts bookings that do not overlap" do
      insert_booking(1, ~U[2026-07-30 09:00:00Z], ~U[2026-07-30 10:00:00Z])
      insert_booking(1, ~U[2026-07-30 10:00:00Z], ~U[2026-07-30 11:00:00Z])

      assert count_bookings() == 2
    end

    test "accepts overlapping bookings in different rooms" do
      insert_booking(1, ~U[2026-07-30 09:00:00Z], ~U[2026-07-30 11:00:00Z])
      insert_booking(2, ~U[2026-07-30 09:00:00Z], ~U[2026-07-30 11:00:00Z])

      assert count_bookings() == 2
    end

    test "rejects overlapping bookings in the same room" do
      insert_booking(1, ~U[2026-07-30 09:00:00Z], ~U[2026-07-30 11:00:00Z])

      exception =
        assert_raise Postgrex.Error, fn ->
          insert_booking(1, ~U[2026-07-30 10:00:00Z], ~U[2026-07-30 12:00:00Z])
        end

      assert exception.postgres.code == :exclusion_violation
      assert exception.postgres.constraint == "range_bookings_period_no_overlap"
      assert count_bookings() == 1
    end

    # An exclusive upper bound means a booking ending at 10:00 and one
    # starting at 10:00 touch without overlapping.
    test "adjacent bookings do not overlap" do
      insert_booking(1, ~U[2026-07-30 09:00:00Z], ~U[2026-07-30 10:00:00Z])
      insert_booking(1, ~U[2026-07-30 10:00:00Z], ~U[2026-07-30 11:00:00Z])

      assert TestRepo.query!(
               "SELECT count(*) FROM range_bookings a JOIN range_bookings b ON a.id < b.id AND a.period -|- b.period"
             ).rows == [[1]]
    end
  end

  defp insert_booking(room_id, starts_at, ends_at) do
    TestRepo.query!(
      "INSERT INTO range_bookings (room_id, period) VALUES ($1, tstzrange($2, $3))",
      [room_id, starts_at, ends_at]
    )
  end

  defp count_bookings do
    [[count]] = TestRepo.query!("SELECT count(*) FROM range_bookings").rows
    count
  end
end

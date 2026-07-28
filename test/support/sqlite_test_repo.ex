defmodule Localize.Ecto.SQLiteTestRepo do
  @moduledoc false

  use Ecto.Repo, otp_app: :localize_ecto, adapter: Ecto.Adapters.SQLite3
end

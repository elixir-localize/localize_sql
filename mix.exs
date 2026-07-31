defmodule LocalizeSql.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/elixir-localize/localize_sql"

  def project do
    [
      app: :localize_sql,
      version: @version,
      name: "Localize SQL",
      source_url: @source_url,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: maybe_elixir_make() ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      make_targets: ["all"],
      make_clean: ["clean"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :ecto_sql],
        flags: [
          :error_handling,
          :unknown,
          :underspecs,
          :extra_return,
          :missing_return
        ]
      ],
      # The audit mix task is CLI glue over `Localize.Ecto.Audit`
      # (which is covered); mix tasks are excluded from coverage
      # measurement as in the localize repo. The test repos are
      # scaffolding from test/support — coverage measures lib/, and the
      # SQLite repo is not even started when the extension is absent.
      test_coverage: [
        ignore_modules: [~r/^Mix\.Tasks\./, Localize.Ecto.TestRepo, Localize.Ecto.SQLiteTestRepo]
      ]
    ]
  end

  def description do
    "SQL database support for Localize: locale-aware ICU collation for Ecto queries on " <>
      "PostgreSQL and SQLite, tagged-decimal composite types with database-side sum, avg, " <>
      "min and max aggregates and arithmetic operators, unit serialization, and range types."
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Readme" => "#{@source_url}/blob/v#{@version}/README.md",
        "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md"
      },
      # Listed file by file rather than by directory so that a local
      # build of the SQLite extension — object files in c_src, the
      # shared library in priv — cannot be published by accident.
      files: [
        "lib",
        "priv/localize_sql",
        "c_src/localize_icu.c",
        "c_src/sqlite3.h",
        "c_src/sqlite3ext.h",
        "c_src/Makefile",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      formatters: ["html", "markdown"],
      extras: [
        "README.md",
        "guides/using_localize_sql.md",
        "guides/collations_in_postgres.md",
        "guides/collations_in_sqlite.md",
        "CHANGELOG.md",
        "LICENSE.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # The SQLite ICU extension is opt-in: it needs a C toolchain and the
  # ICU development libraries, which PostgreSQL-only users have no
  # reason to install. Enable it with the LOCALIZE_SQL_SQLITE_ICU=true
  # environment variable or by setting
  # `config :localize_sql, :sqlite_icu, true` in config.exs. The config
  # key must be in config.exs, not runtime.exs, because it is read at
  # compile time to decide whether to include the :elixir_make compiler.
  defp maybe_elixir_make do
    if sqlite_icu_enabled?() do
      [:elixir_make]
    else
      []
    end
  end

  defp sqlite_icu_enabled? do
    String.downcase(System.get_env("LOCALIZE_SQL_SQLITE_ICU", "false")) == "true" ||
      Application.get_env(:localize_sql, :sqlite_icu, false) == true
  end

  defp deps do
    [
      {:ecto, "~> 3.12"},
      {:localize, "~> 1.0"},
      {:ecto_sql, "~> 3.12", optional: true},
      {:elixir_make, "~> 0.8", optional: true, runtime: false},
      {:postgrex, "~> 0.20", optional: true},
      {:exqlite, "~> 0.35", only: [:dev, :test]},
      {:ecto_sqlite3, "~> 0.21", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :release], runtime: false}
    ] ++ maybe_json_polyfill()
  end

  # json_polyfill (the EEP 68 :json module for OTP 26) is provided for
  # this project's own dev/test/CI only — `only:` dependencies never
  # enter the hex package requirements. OTP 26 consumers add
  # {:json_polyfill, "~> 0.2 or ~> 1.0"} to their own deps, as the
  # localize README documents. The conditional avoids fetching it on
  # OTP >= 27, where :json is built in.
  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0", only: [:dev, :test]}]
    end
  end
end

defmodule LRS.MixProject do
  use Mix.Project

  @source_url "https://github.com/Jump-App/lrs"

  def project do
    [
      app: :lrs,
      version: "0.1.6",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      docs: docs(),
      description: "A Rust NIF for the longest recurring substring algorithm",
      name: "LRS",
      package: package(),
      aliases: aliases(),
      preferred_cli_env: [
        check: :test
      ]
    ]
  end

  def application do
    []
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end

  defp deps do
    [
      {:rustler, ">= 0.0.0", optional: true},
      {:rustler_precompiled, "~> 0.8"}
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "native/lrs/.cargo",
        "native/lrs/src",
        "native/lrs/Cargo*",
        "checksum-*.exs",
        "mix.exs"
      ],
      maintainers: ["Tyler Young"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      check: [
        "clean",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test --warnings-as-errors"
      ]
    ]
  end
end

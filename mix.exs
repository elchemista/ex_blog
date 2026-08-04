defmodule ExBlog.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_blog,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      dialyzer: [
        flags: [:unmatched_returns, :error_handling],
        plt_add_apps: [:ex_unit, :mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ExBlog.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:req, "~> 0.7.2", override: true},
      {:cors_plug, "~> 3.0"},
      {:argon2_elixir, "~> 4.1"},
      {:qr_code, "~> 3.2"},
      {:mdex, "~> 0.13.5"},
      {:yaml_elixir, "~> 2.12"},
      {:decimal, "~> 3.1"},
      {:slugify, github: "elchemista/slugify", branch: "master", depth: 1},
      {:ex_gram, github: "elchemista/ex_gram", branch: "main", depth: 1},
      {:spectre, github: "elchemista/spectre", branch: "main", depth: 1, override: true},
      {:spectre_prism,
       github: "elchemista/spectre_prism", branch: "main", depth: 1, override: true},
      {:spectre_beam,
       github: "elchemista/spectre_beam", branch: "main", depth: 1, override: true},
      {:spectre_kinetic,
       github: "elchemista/spectre_kinetic", branch: "main", depth: 1, override: true},
      {:spectre_lens,
       github: "elchemista/spectre_lens", branch: "main", depth: 1, override: true},
      {:ex_fastembed,
       github: "elchemista/ex_fastembed",
       branch: "master",
       only: [:dev, :test],
       runtime: false,
       depth: 1},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind ex_blog", "esbuild ex_blog"],
      "assets.deploy": [
        "tailwind ex_blog --minify",
        "esbuild ex_blog --minify",
        "phx.digest"
      ],
      "spectre.dataset.setup": ["ex_blog.spectre.dataset.build"],
      "spectre.classifier.setup": [
        "spectre.dataset.setup",
        "spectre.classifier.download_model --model intfloat/multilingual-e5-small",
        "spectre.classifier.train training/dataset.json artifacts/spectre --model intfloat/multilingual-e5-small --accept-threshold 0.89 --margin-threshold 0.008 --high-confidence-threshold 0.95"
      ],
      precommit: [
        "ex_blog.spectre.dataset.build --check",
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end
end

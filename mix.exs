defmodule ExCodecs.MixProject do
  use Mix.Project

  @version "0.2.3"
  @source_url "https://github.com/thanos/codecs"

  def project do
    [
      app: :ex_codecs,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      rustler_precompiled: rustler_precompiled(),
      docs: docs(),
      package: package(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [
        tool: ExCoveralls,
        ignore_modules: [ExCodecs.Native],
        threshold: 95
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.github": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        benchmarks: :bench
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExCodecs.Application, []}
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.36", optional: true},
      {:rustler_precompiled, "~> 0.8"},
      {:stream_data, "~> 1.1", only: [:test, :dev]},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.36", only: :dev, runtime: false},
      {:benchee, "~> 1.3", only: :bench},
      {:benchee_html, "~> 1.0", only: :bench}
    ]
  end

  defp rustler_precompiled do
    [
      targets: [
        "aarch64-apple-darwin",
        "x86_64-apple-darwin",
        "x86_64-unknown-linux-gnu",
        "x86_64-unknown-linux-musl",
        "aarch64-unknown-linux-gnu",
        "aarch64-unknown-linux-musl",
        "x86_64-pc-windows-msvc"
      ],
      mode: :release,
      nif_versions: ["2.17"]
    ]
  end

  defp package do
    [
      description:
        "An extensible BEAM-native codec framework for Elixir — compression and spatial formats",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/ex_codecs"
      },
      files: [
        "lib",
        "native/ex_codecs_native/src",
        "native/ex_codecs_native/.cargo",
        "native/ex_codecs_native/Cargo.toml",
        "native/ex_codecs_native/Cargo.lock",
        "priv",
        "guides",
        "livebooks",
        "docs/spatial_formats.md",
        "checksum-*.exs",
        "mix.exs",
        "README.md",
        "LICENSE"
      ]
    ]
  end

  defp docs do
    [
      main: "ExCodecs",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras:
        [
          "guides/benchmarking_methodology.md",
          "guides/choosing_compression_codec.md",
          "guides/codec_fundamentals.md",
          "guides/compression_fundamentals.md",
          "guides/native_architecture.md",
          "guides/runtime_codec_discovery.md",
          "guides/understanding_blosc2.md",
          "guides/understanding_bzip2.md",
          "guides/understanding_lz4.md",
          "guides/understanding_snappy.md",
          "guides/understanding_spatial_codecs.md",
          "guides/understanding_zstd.md",
          "livebooks/01_introduction.livemd",
          "livebooks/02_compression_fundamentals.livemd",
          "livebooks/03_codec_comparison.livemd",
          "livebooks/04_building_storage_systems.livemd",
          "livebooks/05_zarr_style_workloads.livemd",
          "livebooks/06_spatial_codecs.livemd",
          "docs/spatial_formats.md"
        ],
      groups_for_extras: [
        Guides: ~r"guides/",
        Livebooks: ~r"livebooks/",
        "Architecture & formats": ~r"docs/"
      ]
    ]
  end

  defp elixirc_paths(:bench), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "rust.lint": [
        "cmd cargo clippy --manifest-path native/ex_codecs_native/Cargo.toml -- -D warnings"
      ],
      "rust.test": ["cmd cargo test --manifest-path native/ex_codecs_native/Cargo.toml"],
      benchmarks: ["run bench/run.exs"]
    ]
  end
end

import Config

config :ex_codecs,
  stream_data_runs: 100,
  stream_data_max_size: 10_240

config :excoveralls,
  output_dir: "cover/",
  coverage_options: [
    treat_no_relevant_lines_as_covered: false,
    local_only: true
  ],
  skip_files: [
    ~r"test/support/",
    ~r"bench/",
    ~r"lib.ex_codecs.native.ex$"
  ]

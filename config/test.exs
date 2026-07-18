import Config

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

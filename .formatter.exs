[
  line_length: 120,
  inputs:
    Enum.flat_map(["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"], &Path.wildcard(&1, match_dot: true)) --
      ["checksum-Elixir.LRS.exs"]
]

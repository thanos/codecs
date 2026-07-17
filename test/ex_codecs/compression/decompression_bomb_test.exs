defmodule ExCodecs.Compression.DecompressionBombTest do
  use ExUnit.Case, async: true

  @moduledoc false

  # Highly compressible payload: 64 KiB of zeros → tiny compressed bomb.
  # Large enough for a clear ratio, small enough to stay fast in CI.
  @expanded_size 65_536
  @bomb_raw :binary.copy(<<0>>, @expanded_size)
  # Bound clearly below the expanded size so the decode must reject.
  @tight_limit 1_024

  @codecs [
    {:zstd, []},
    {:lz4, []},
    {:snappy, []},
    {:bzip2, []},
    {:blosc2, [cname: :lz4, shuffle: :none, typesize: 1]}
  ]

  describe "bounded decompression bombs" do
    for {codec, encode_opts} <- @codecs do
      @codec codec
      @encode_opts encode_opts

      test "#{codec} rejects a high-ratio zeros bomb under a tight max_output_size" do
        assert {:ok, bomb} = ExCodecs.encode(@codec, @bomb_raw, @encode_opts)

        # Bomb shape: compressed input is much smaller than the expanded size.
        assert byte_size(bomb) * 10 < @expanded_size

        assert {:error, %ExCodecs.Error{reason: :output_limit_exceeded, codec: @codec}} =
                 ExCodecs.decode(@codec, bomb, max_output_size: @tight_limit)
      end

      test "#{codec} succeeds when max_output_size is above the expanded size" do
        assert {:ok, bomb} = ExCodecs.encode(@codec, @bomb_raw, @encode_opts)

        assert {:ok, @bomb_raw} =
                 ExCodecs.decode(@codec, bomb, max_output_size: @expanded_size)
      end
    end

    test "default max_output_size (256 MiB) accepts the zeros bomb" do
      assert {:ok, bomb} = ExCodecs.encode(:zstd, @bomb_raw)
      assert {:ok, @bomb_raw} = ExCodecs.decode(:zstd, bomb)
    end
  end
end

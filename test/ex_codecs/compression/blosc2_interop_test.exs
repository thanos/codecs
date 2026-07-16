defmodule ExCodecs.Compression.Blosc2InteropTest do
  use ExUnit.Case, async: true

  @moduletag :blosc2_interop

  @fixture_dir Path.expand("../../fixtures/blosc2", __DIR__)

  @goldens [
    "lz4_noshuffle_t1.bin",
    "lz4_shuffle_t8.bin",
    "zstd_shuffle_t8.bin",
    "blosclz_noshuffle.bin",
    "lz4hc_noshuffle.bin",
    "zlib_noshuffle.bin",
    "lz4_bitshuffle_t8.bin"
  ]

  describe "python-blosc2 golden chunks" do
    for name <- @goldens do
      test "decompresses #{name}" do
        bin = File.read!(Path.join(@fixture_dir, unquote(name)))
        src = File.read!(Path.join(@fixture_dir, String.replace(unquote(name), ".bin", ".src")))

        assert {:ok, decompressed} = ExCodecs.decode(:blosc2, bin)
        assert decompressed == src
      end
    end
  end

  describe "round-trip all official cnames" do
    test "blosclz lz4 lz4hc zlib zstd with filters" do
      data = :crypto.strong_rand_bytes(4096)
      floats = for i <- 1..512, into: <<>>, do: <<i * 0.125::float-64-little>>

      for cname <- [:blosclz, :lz4, :lz4hc, :zlib, :zstd] do
        assert {:ok, c} = ExCodecs.encode(:blosc2, data, cname: cname, shuffle: :none, typesize: 1)
        assert {:ok, ^data} = ExCodecs.decode(:blosc2, c)
      end

      for {shuffle, typesize, payload} <- [
            {:byte, 8, floats},
            {:bit, 8, floats},
            {:none, 1, data}
          ] do
        assert {:ok, c} =
                 ExCodecs.encode(:blosc2, payload,
                   cname: :lz4,
                   clevel: 5,
                   shuffle: shuffle,
                   typesize: typesize
                 )

        assert {:ok, ^payload} = ExCodecs.decode(:blosc2, c)
      end
    end

    test "rejects snappy" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.encode(:blosc2, "x", cname: :snappy)
    end
  end
end

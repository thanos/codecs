defmodule ExCodecs.ConcurrentTest do
  use ExUnit.Case, async: true

  describe "concurrent usage" do
    test "handles concurrent compression/decompression" do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            data = :crypto.strong_rand_bytes(1024 + i)
            {:ok, compressed} = ExCodecs.encode(:zstd, data, level: rem(i, 22) + 1)
            {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
            {i, data == decompressed}
          end)
        end

      results = Task.await_many(tasks, 30_000)

      for {_i, success} <- results do
        assert success, "Concurrent round-trip failed"
      end
    end

    test "handles concurrent codec mixing" do
      codecs = [:zstd, :lz4, :snappy, :bzip2]

      tasks =
        for codec <- codecs,
            _i <- 1..10 do
          Task.async(fn ->
            data = :crypto.strong_rand_bytes(1024)
            {:ok, compressed} = ExCodecs.encode(codec, data)
            {:ok, decompressed} = ExCodecs.decode(codec, compressed)
            {codec, data == decompressed}
          end)
        end

      results = Task.await_many(tasks, 30_000)

      for {codec, success} <- results do
        assert success, "Concurrent round-trip failed for #{codec}"
      end
    end
  end
end

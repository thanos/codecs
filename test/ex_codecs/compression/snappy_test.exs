defmodule ExCodecs.Compression.SnappyTest do
  use ExUnit.Case, async: true

  describe "encode/2" do
    test "compresses data" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, compressed} = ExCodecs.Compression.Snappy.encode(data, [])
      assert is_binary(compressed)
    end

    test "handles empty data" do
      assert {:ok, compressed} = ExCodecs.Compression.Snappy.encode("", [])
      assert {:ok, decompressed} = ExCodecs.Compression.Snappy.decode(compressed, [])
      assert decompressed == ""
    end

    test "handles repeating data" do
      data = String.duplicate("hello world ", 1000)
      assert {:ok, compressed} = ExCodecs.Compression.Snappy.encode(data, [])
      assert byte_size(compressed) < byte_size(data)
    end
  end

  describe "decode/2" do
    test "round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = ExCodecs.Compression.Snappy.encode(data, [])
      {:ok, decompressed} = ExCodecs.Compression.Snappy.decode(compressed, [])
      assert decompressed == data
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = ExCodecs.Compression.Snappy.__codec_info__()
      assert info.name == :snappy
      assert info.category == :compression
      assert info.configurable? == false
    end
  end
end

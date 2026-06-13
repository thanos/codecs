defmodule ExCodecs.Compression.SnappyTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Compression.Snappy

  describe "encode/2" do
    test "compresses data" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, compressed} = Snappy.encode(data, [])
      assert is_binary(compressed)
    end

    test "handles empty data" do
      assert {:ok, compressed} = Snappy.encode("", [])
      assert {:ok, decompressed} = Snappy.decode(compressed, [])
      assert decompressed == ""
    end

    test "handles repeating data" do
      data = String.duplicate("hello world ", 1000)
      assert {:ok, compressed} = Snappy.encode(data, [])
      assert byte_size(compressed) < byte_size(data)
    end

    test "round-trips highly compressible data" do
      data = :binary.copy(<<0>>, 1_000_000)
      assert {:ok, compressed} = Snappy.encode(data, [])
      assert {:ok, decompressed} = Snappy.decode(compressed, [])
      assert decompressed == data
    end
  end

  describe "decode/2" do
    test "round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = Snappy.encode(data, [])
      {:ok, decompressed} = Snappy.decode(compressed, [])
      assert decompressed == data
    end

    test "returns error for corrupt data" do
      assert {:error, _} = Snappy.decode(<<0, 1, 2, 3>>, [])
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Snappy.__codec_info__()
      assert info.name == :snappy
      assert info.category == :compression
      assert info.configurable? == false
      assert info.native? == true
      assert info.streaming? == false
    end
  end
end

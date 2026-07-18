defmodule ExCodecs.Compression.Lz4Test do
  use ExUnit.Case, async: true

  @moduletag :doctest
  doctest ExCodecs.Compression.Lz4

  alias ExCodecs.Compression.Lz4

  describe "encode/2" do
    test "round-trips compressible data" do
      data = String.duplicate("ab", 4096)
      assert {:ok, compressed} = Lz4.encode(data, [])
      assert {:ok, ^data} = Lz4.decode(compressed, [])
      assert byte_size(compressed) < byte_size(data)
    end

    test "compresses highly compressible data" do
      data = :binary.copy(<<0>>, 1_000_000)
      assert {:ok, compressed} = Lz4.encode(data, [])
      assert {:ok, decompressed} = Lz4.decode(compressed, [])
      assert decompressed == data
    end

    test "compresses repeated string data" do
      data = String.duplicate("ab", 500_000)
      assert {:ok, compressed} = Lz4.encode(data, [])
      assert {:ok, decompressed} = Lz4.decode(compressed, [])
      assert decompressed == data
    end

    test "compresses random data" do
      data = :crypto.strong_rand_bytes(4096)
      assert {:ok, compressed} = Lz4.encode(data, [])
      assert {:ok, decompressed} = Lz4.decode(compressed, [])
      assert decompressed == data
    end

    test "handles empty data" do
      assert {:ok, compressed} = Lz4.encode("", [])
      assert {:ok, decompressed} = Lz4.decode(compressed, [])
      assert decompressed == ""
    end

    test "handles single byte data" do
      assert {:ok, compressed} = Lz4.encode(<<42>>, [])
      assert {:ok, decompressed} = Lz4.decode(compressed, [])
      assert decompressed == <<42>>
    end
  end

  describe "decode/2" do
    test "returns error for corrupt data" do
      assert {:error, _} = Lz4.decode(<<0, 1, 2, 3>>, [])
    end

    test "rejects decompress when max_output_size is too small" do
      data = String.duplicate("ab", 10_000)
      {:ok, compressed} = Lz4.encode(data, [])

      assert {:error, %ExCodecs.Error{reason: :output_limit_exceeded}} =
               Lz4.decode(compressed, max_output_size: 16)
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Lz4.__codec_info__()
      assert info.name == :lz4
      assert info.category == :compression
      assert info.configurable? == false
      assert info.native? == true
      assert info.streaming? == false
    end
  end
end

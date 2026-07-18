defmodule ExCodecs.Compression.Bzip2Test do
  use ExUnit.Case, async: true

  @moduletag :doctest
  doctest ExCodecs.Compression.Bzip2

  alias ExCodecs.Compression.Bzip2

  describe "encode/2" do
    test "round-trips data at default block size" do
      data = String.duplicate("Hello, World! ", 256)
      assert {:ok, compressed} = Bzip2.encode(data, [])
      assert {:ok, ^data} = Bzip2.decode(compressed, [])
      assert byte_size(compressed) < byte_size(data)
    end

    test "round-trips data at every block size 1..9" do
      data = String.duplicate("Hello, World! This is a compression test. ", 256)

      for bs <- 1..9 do
        assert {:ok, compressed} = Bzip2.encode(data, block_size: bs)
        assert {:ok, ^data} = Bzip2.decode(compressed, [])
      end
    end

    test "block_size affects compression output" do
      data = String.duplicate("Hello, World! ", 10_000)
      {:ok, c1} = Bzip2.encode(data, block_size: 1)
      {:ok, c9} = Bzip2.encode(data, block_size: 9)
      assert is_binary(c1)
      assert is_binary(c9)
      assert byte_size(c9) <= byte_size(c1)
    end

    test "handles empty data" do
      assert {:ok, compressed} = Bzip2.encode("", [])
      assert {:ok, decompressed} = Bzip2.decode(compressed, [])
      assert decompressed == ""
    end

    test "returns error for invalid block size" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Bzip2.encode("data", block_size: 0)

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Bzip2.encode("data", block_size: 10)
    end

    test "round-trips highly compressible data" do
      data = :binary.copy(<<0>>, 1_000_000)
      assert {:ok, compressed} = Bzip2.encode(data, [])
      assert {:ok, decompressed} = Bzip2.decode(compressed, [])
      assert decompressed == data
    end
  end

  describe "decode/2" do
    test "round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = Bzip2.encode(data, [])
      {:ok, decompressed} = Bzip2.decode(compressed, [])
      assert decompressed == data
    end

    test "returns error for corrupt data" do
      assert {:error, _} = Bzip2.decode(<<0, 1, 2, 3>>, [])
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Bzip2.__codec_info__()
      assert info.name == :bzip2
      assert info.category == :compression
      assert info.configurable? == true
      assert info.native? == true
      assert info.streaming? == false
    end
  end
end

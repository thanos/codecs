defmodule ExCodecs.Compression.Blosc2Test do
  use ExUnit.Case, async: true

  @moduletag :doctest
  doctest ExCodecs.Compression.Blosc2

  alias ExCodecs.Compression.Blosc2

  describe "encode/2" do
    test "compresses data with default options" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, compressed} = Blosc2.encode(data, [])
      assert is_binary(compressed)
    end

    test "compresses data with zstd codec" do
      data = :crypto.strong_rand_bytes(4096)

      assert {:ok, compressed} =
               Blosc2.encode(data, cname: :zstd, clevel: 5)

      assert {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == data
    end

    test "compresses data with different shuffle modes" do
      data = :crypto.strong_rand_bytes(4096)

      for shuffle <- [:none, :byte, :bit] do
        assert {:ok, compressed} =
                 Blosc2.encode(data, shuffle: shuffle)

        assert {:ok, decompressed} = Blosc2.decode(compressed, [])
        assert decompressed == data
      end
    end

    test "compresses highly compressible data" do
      data = :binary.copy(<<0>>, 1_000_000)
      assert {:ok, compressed} = Blosc2.encode(data, cname: :lz4, shuffle: :none, typesize: 1)
      assert {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == data
    end

    test "compresses highly compressible data with zstd inner codec" do
      data = :binary.copy(<<0>>, 1_000_000)

      assert {:ok, compressed} =
               Blosc2.encode(data, cname: :zstd, clevel: 5, shuffle: :none, typesize: 1)

      assert {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == data
    end

    test "round-trips random data with typesize 4 and 8, all shuffle modes" do
      data = :crypto.strong_rand_bytes(10_000)

      for typesize <- [4, 8], shuffle <- [:none, :byte, :bit] do
        assert {:ok, compressed} =
                 Blosc2.encode(data, cname: :lz4, clevel: 5, shuffle: shuffle, typesize: typesize)

        assert {:ok, decompressed} = Blosc2.decode(compressed, [])
        assert decompressed == data
      end
    end

    test "round-trips uniform float64 data with byte shuffle (highly compressible)" do
      floats = for _ <- 1..1250, do: <<1.0::float-64>>
      data = IO.iodata_to_binary(floats)
      assert byte_size(data) == 10_000

      for cname <- [:lz4, :zstd] do
        assert {:ok, compressed} =
                 Blosc2.encode(data, cname: cname, clevel: 5, shuffle: :byte, typesize: 8)

        assert {:ok, decompressed} = Blosc2.decode(compressed, [])
        assert decompressed == data
      end
    end

    test "round-trips sequential int32 data with byte shuffle" do
      ints = for i <- 1..2500, do: <<i::signed-integer-size(32)>>
      data = IO.iodata_to_binary(ints)
      assert byte_size(data) == 10_000
      assert {:ok, compressed} = Blosc2.encode(data, cname: :lz4, shuffle: :byte, typesize: 4)
      assert {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == data
    end

    test "round-trips sequential float64 data with bit shuffle" do
      floats = for i <- 1..2048, into: <<>>, do: <<i * 0.125::float-size(64)-little>>
      assert {:ok, compressed} = Blosc2.encode(floats, cname: :zstd, shuffle: :bit, typesize: 8)
      assert {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == floats
    end

    test "clevel affects compression output size" do
      data = :crypto.strong_rand_bytes(10_000)
      {:ok, c1} = Blosc2.encode(data, cname: :zstd, clevel: 1, shuffle: :none)
      {:ok, c9} = Blosc2.encode(data, cname: :zstd, clevel: 9, shuffle: :none)
      assert byte_size(c9) <= byte_size(c1)
    end

    test "no shuffle vs byte shuffle vs bit shuffle all round-trip" do
      data = :crypto.strong_rand_bytes(8192)
      {:ok, c_none} = Blosc2.encode(data, shuffle: :none, typesize: 1)
      {:ok, c_byte} = Blosc2.encode(data, shuffle: :byte, typesize: 4)
      {:ok, c_bit} = Blosc2.encode(data, shuffle: :bit, typesize: 4)
      assert {:ok, ^data} = Blosc2.decode(c_none, [])
      assert {:ok, ^data} = Blosc2.decode(c_byte, [])
      assert {:ok, ^data} = Blosc2.decode(c_bit, [])
    end

    test "validates cname option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", cname: :invalid)
    end

    test "validates clevel option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", clevel: 10)
    end

    test "validates shuffle option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", shuffle: :invalid)
    end

    test "accepts bit shuffle option" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, _} = Blosc2.encode(data, shuffle: :bit)
    end

    test "validates typesize option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", typesize: 0)
    end
  end

  describe "decode/2" do
    test "round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = Blosc2.encode(data, [])
      {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == data
    end

    test "returns error for invalid magic" do
      assert {:error, %ExCodecs.Error{reason: :decompression_failed}} =
               Blosc2.decode(<<0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, [])
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Blosc2.__codec_info__()
      assert info.name == :blosc2
      assert info.category == :compression
      assert info.configurable? == true
      assert info.streaming? == false
      assert info.native? == true
      assert is_binary(info.version)
    end
  end

  describe "c-blosc2 cnames" do
    test "accepts blosclz and lz4hc" do
      data = :crypto.strong_rand_bytes(1024)

      assert {:ok, c} = Blosc2.encode(data, cname: :blosclz, shuffle: :none)
      assert {:ok, ^data} = Blosc2.decode(c, [])

      assert {:ok, c} = Blosc2.encode(data, cname: :lz4hc, shuffle: :none)
      assert {:ok, ^data} = Blosc2.decode(c, [])
    end

    test "round-trips official cnames" do
      data = :crypto.strong_rand_bytes(2048)

      for cname <- [:blosclz, :lz4, :lz4hc, :zlib, :zstd] do
        assert {:ok, compressed} = Blosc2.encode(data, cname: cname, shuffle: :none, typesize: 1)
        assert {:ok, ^data} = Blosc2.decode(compressed, [])
      end
    end

    test "rejects snappy" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", cname: :snappy)
    end
  end
end

defmodule ExCodecs.PropertyExpansionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExCodecs.Error
  alias ExCodecs.Spatial.{Bounds, Point}

  @moduletag timeout: 60_000

  property "zstd round-trips across small levels" do
    check all(
            data <- binary(min_length: 0, max_length: 512),
            level <- integer(1..5),
            max_runs: 25
          ) do
      {:ok, compressed} = ExCodecs.encode(:zstd, data, level: level)
      {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == data
    end
  end

  property "bzip2 round-trips across block sizes" do
    check all(
            data <- binary(min_length: 1, max_length: 256),
            block_size <- integer(1..9),
            max_runs: 20
          ) do
      {:ok, compressed} = ExCodecs.encode(:bzip2, data, block_size: block_size)
      {:ok, decompressed} = ExCodecs.decode(:bzip2, compressed)
      assert decompressed == data
    end
  end

  property "blosc2 round-trips across clevel with typesize-aligned data" do
    check all(
            typesize <- integer(1..8),
            n_elems <- integer(1..16),
            clevel <- integer(0..9),
            cname <- member_of([:lz4, :zstd]),
            shuffle <- member_of([:none, :byte]),
            max_runs: 30
          ) do
      data = :binary.copy(<<7>>, typesize * n_elems)

      {:ok, compressed} =
        ExCodecs.encode(:blosc2, data,
          cname: cname,
          clevel: clevel,
          shuffle: shuffle,
          typesize: typesize
        )

      {:ok, decompressed} = ExCodecs.decode(:blosc2, compressed)
      assert decompressed == data
    end
  end

  property "zstd max_output_size rejects undersized and accepts exact" do
    check all(data <- binary(min_length: 2, max_length: 256), max_runs: 25) do
      {:ok, compressed} = ExCodecs.encode(:zstd, data)

      assert {:error, %Error{reason: :output_limit_exceeded}} =
               ExCodecs.decode(:zstd, compressed, max_output_size: byte_size(data) - 1)

      assert {:ok, ^data} =
               ExCodecs.decode(:zstd, compressed, max_output_size: byte_size(data))
    end
  end

  property "lz4 max_output_size rejects undersized and accepts exact" do
    check all(data <- binary(min_length: 2, max_length: 256), max_runs: 25) do
      {:ok, compressed} = ExCodecs.encode(:lz4, data)

      assert {:error, %Error{reason: :output_limit_exceeded}} =
               ExCodecs.decode(:lz4, compressed, max_output_size: byte_size(data) - 1)

      assert {:ok, ^data} =
               ExCodecs.decode(:lz4, compressed, max_output_size: byte_size(data))
    end
  end

  property "truncation never crashes framed codecs" do
    check all(
            codec <- member_of([:zstd, :bzip2, :blosc2]),
            data <- binary(min_length: 8, max_length: 128),
            max_runs: 40
          ) do
      encode_opts =
        case codec do
          :blosc2 -> [shuffle: :none, typesize: 1]
          _ -> []
        end

      {:ok, compressed} = ExCodecs.encode(codec, data, encode_opts)
      truncated = corrupt(compressed, :truncate)

      assert {:error, %Error{}} = ExCodecs.decode(codec, truncated)
    end
  end

  property "magic-byte corruption never crashes zstd or bzip2" do
    check all(
            codec <- member_of([:zstd, :bzip2]),
            data <- binary(min_length: 8, max_length: 128),
            max_runs: 40
          ) do
      {:ok, compressed} = ExCodecs.encode(codec, data)
      corrupted = corrupt(compressed, :flip_magic)

      assert {:error, %Error{}} = ExCodecs.decode(codec, corrupted)
    end
  end

  property "Bounds.from_points contains every input point" do
    check all(
            points <- list_of(point_gen(), min_length: 1, max_length: 20),
            max_runs: 40
          ) do
      bounds = Bounds.from_points(points)
      refute is_nil(bounds)

      for %Point{x: x, y: y, z: z} <- points do
        assert Bounds.contains?(bounds, {x, y, z})
      end
    end
  end

  defp point_gen do
    gen all(
          x <- float(min: -1000.0, max: 1000.0),
          y <- float(min: -1000.0, max: 1000.0),
          z <- float(min: -1000.0, max: 1000.0)
        ) do
      Point.new(x, y, z)
    end
  end

  defp corrupt(bin, :truncate) when byte_size(bin) > 1 do
    binary_part(bin, 0, byte_size(bin) - 1)
  end

  defp corrupt(_bin, :truncate), do: <<>>

  # Flip the frame magic / leading byte so parsers reject without relying on
  # optional content checksums (zstd may accept mid-frame bit flips).
  defp corrupt(<<byte, rest::binary>>, :flip_magic) do
    <<Bitwise.bxor(byte, 0xFF), rest::binary>>
  end
end

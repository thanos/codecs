defmodule ExCodecs.NIFTest do
  use ExUnit.Case, async: true

  alias ExCodecs.NIF

  describe "wrap/2" do
    test "passes through success tuples" do
      assert {:ok, "data"} = NIF.wrap(:zstd, {:ok, "data"})
    end

    test "wraps compression_failed error" do
      assert {:error, %ExCodecs.Error{reason: :compression_failed, codec: :zstd}} =
               NIF.wrap(:zstd, {:error, :compression_failed})
    end

    test "wraps decompression_failed error" do
      assert {:error, %ExCodecs.Error{reason: :decompression_failed, codec: :lz4}} =
               NIF.wrap(:lz4, {:error, :decompression_failed})
    end

    test "wraps output_limit_exceeded error" do
      assert {:error, %ExCodecs.Error{reason: :output_limit_exceeded, codec: :zstd}} =
               NIF.wrap(:zstd, {:error, :output_limit_exceeded})
    end

    test "wraps invalid_data error" do
      assert {:error, %ExCodecs.Error{reason: :invalid_data, codec: :blosc2}} =
               NIF.wrap(:blosc2, {:error, :invalid_data})
    end

    test "wraps invalid_options error" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options, codec: :bzip2}} =
               NIF.wrap(:bzip2, {:error, :invalid_options})
    end

    test "wraps unknown error atoms" do
      assert {:error, %ExCodecs.Error{reason: :invalid_data, codec: :snappy, details: :some_unknown_error}} =
               NIF.wrap(:snappy, {:error, :some_unknown_error})
    end
  end
end

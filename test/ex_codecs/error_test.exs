defmodule ExCodecs.ErrorTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Error

  describe "new/2" do
    test "creates error with default message" do
      error = Error.new(:unsupported_codec)
      assert error.reason == :unsupported_codec
      assert error.message == "The specified codec is not supported"
      assert error.codec == nil
      assert error.details == nil
    end

    test "creates error with custom message" do
      error = Error.new(:invalid_data, message: "custom message")
      assert error.message == "custom message"
    end

    test "creates error with codec" do
      error = Error.new(:codec_unavailable, codec: :zstd)
      assert error.codec == :zstd
    end

    test "creates error with details" do
      error = Error.new(:compression_failed, details: %{size: 1024})
      assert error.details == %{size: 1024}
    end

    test "creates error for all known reasons" do
      reasons = [
        :unsupported_codec,
        :codec_unavailable,
        :invalid_data,
        :invalid_options,
        :compression_failed,
        :decompression_failed,
        :nif_not_loaded
      ]

      for reason <- reasons do
        error = Error.new(reason)
        assert error.reason == reason
        assert is_binary(error.message)
      end
    end
  end

  describe "error/2" do
    test "returns error tuple" do
      assert {:error, %Error{reason: :unsupported_codec}} = Error.error(:unsupported_codec)
    end

    test "returns error tuple with options" do
      assert {:error, %Error{codec: :zstd}} = Error.error(:compression_failed, codec: :zstd)
    end
  end

  describe "from_nif/2" do
    test "wraps NIF error with codec name" do
      assert {:error, %Error{codec: :zstd}} = Error.from_nif({:error, :some_reason}, :zstd)
    end
  end

  describe "matches?/2" do
    test "matches error reason" do
      {:error, error} = Error.error(:unsupported_codec)
      assert Error.matches?({:error, error}, :unsupported_codec) == true
      assert Error.matches?({:error, error}, :invalid_data) == false
    end

    test "returns false for non-matching tuples" do
      {:error, error} = Error.error(:unsupported_codec)
      assert Error.matches?({:ok, error}, :unsupported_codec) == false
    end
  end
end

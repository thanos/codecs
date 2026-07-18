defmodule ExCodecs.ApplicationTest do
  use ExUnit.Case, async: false

  alias ExCodecs.Application

  describe "codec_available?/2" do
    test "a NIF-backed codec is unavailable when the NIF is not loaded" do
      assert Application.codec_available?(NifBackedCodec, false) == false
    end

    test "a NIF-backed codec is available when the NIF is loaded" do
      assert Application.codec_available?(NifBackedCodec, true) == true
    end

    test "a pure-Elixir codec is available regardless of NIF load state" do
      assert Application.codec_available?(PureElixirCodec, false) == true
      assert Application.codec_available?(PureElixirCodec, true) == true
    end

    test "a module missing the codec callbacks is unavailable" do
      assert Application.codec_available?(NotACodec, true) == false
    end
  end
end

defmodule NifBackedCodec do
  def __codec_info__ do
    %{native?: true, streaming?: false, configurable?: false, version: "test"}
  end

  def encode(_data, _opts), do: {:ok, <<>>}
  def decode(_data, _opts), do: {:ok, <<>>}
end

defmodule PureElixirCodec do
  def __codec_info__ do
    %{native?: false, streaming?: false, configurable?: false, version: "test"}
  end

  def encode(_data, _opts), do: {:ok, <<>>}
  def decode(_data, _opts), do: {:ok, <<>>}
end

defmodule NotACodec do
  def __codec_info__, do: %{native?: false, streaming?: false, configurable?: false}
end

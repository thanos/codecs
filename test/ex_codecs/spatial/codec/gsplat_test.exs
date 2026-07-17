defmodule ExCodecs.Spatial.Codec.GsplatTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.Codec.Gsplat
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud}

  test "round-trips Gaussians" do
    cloud =
      GaussianCloud.new([
        Gaussian.new({1.0, 2.0, 3.0},
          color: {0.1, 0.2, 0.3},
          opacity: 0.9,
          scale: {0.2, 0.3, 0.4},
          rotation: {0.9, 0.1, 0.0, 0.0}
        )
      ])

    assert {:ok, bin} = Gsplat.encode(cloud)
    assert String.starts_with?(bin, "GSPL")
    assert {:ok, decoded} = Gsplat.decode(bin)
    [g] = decoded.gaussians
    assert_in_delta elem(g.position, 2), 3.0, 0.0001
    assert_in_delta g.opacity, 0.9, 0.0001
  end

  test "round-trips SH rest coefficients" do
    cloud =
      GaussianCloud.new([
        Gaussian.new({0.0, 0.0, 0.0},
          color: {0.5, 0.5, 0.5},
          sh: [[0.5, 0.5, 0.5], [0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
        )
      ])

    assert {:ok, bin} = Gsplat.encode(cloud)
    assert {:ok, decoded} = Gsplat.decode(bin)
    [g] = decoded.gaussians
    assert is_list(g.sh)
    assert length(List.flatten(tl(g.sh))) == 6
  end

  test "stream_decode from file yields Gaussians incrementally" do
    cloud =
      GaussianCloud.new([
        Gaussian.new({1.0, 0.0, 0.0}, opacity: 0.5),
        Gaussian.new({0.0, 1.0, 0.0},
          color: {0.2, 0.3, 0.4},
          sh: [[0.2, 0.3, 0.4], [0.1, 0.1, 0.1]]
        )
      ])

    assert {:ok, bin} = Gsplat.encode(cloud)

    path =
      Path.join(
        System.tmp_dir!(),
        "ex_codecs_gspl_stream_#{System.unique_integer([:positive])}.gspl"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, bin)

    gs = Gsplat.stream_decode(path, source: :file) |> Enum.to_list()
    assert length(gs) == 2
    assert_in_delta hd(gs).opacity, 0.5, 0.0001
    assert is_list(List.last(gs).sh)
  end

  test "stream_decode from truncated file yields invalid_data" do
    cloud = GaussianCloud.new([Gaussian.new({1.0, 2.0, 3.0}), Gaussian.new({4.0, 5.0, 6.0})])
    assert {:ok, bin} = Gsplat.encode(cloud)
    truncated = binary_part(bin, 0, 30)

    path =
      Path.join(
        System.tmp_dir!(),
        "ex_codecs_gspl_trunc_#{System.unique_integer([:positive])}.gspl"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, truncated)

    assert [{:error, %{reason: :invalid_data, codec: :gsplat}}] =
             Gsplat.stream_decode(path, source: :file) |> Enum.to_list()
  end

  test "stream_encode_to_file with schema round-trips" do
    gs = [
      Gaussian.new({1.0, 2.0, 3.0}, opacity: 0.5),
      Gaussian.new({0.0, 1.0, 0.0}, color: {0.2, 0.3, 0.4})
    ]

    path =
      Path.join(
        System.tmp_dir!(),
        "ex_codecs_gspl_enc_#{System.unique_integer([:positive])}.gspl"
      )

    on_exit(fn -> File.rm(path) end)

    assert :ok = Gsplat.stream_encode_to_file(gs, path, schema: [])
    assert {:ok, <<"GSPL", _::binary>> = bin} = File.read(path)
    assert {:ok, decoded} = Gsplat.decode(bin)
    assert length(decoded.gaussians) == 2
    assert_in_delta hd(decoded.gaussians).opacity, 0.5, 0.0001
  end

  test "stream_encode_to_file requires schema" do
    assert {:error, %{reason: :invalid_options}} =
             Gsplat.stream_encode_to_file([Gaussian.new({0, 0, 0})], "x.gspl")
  end
end

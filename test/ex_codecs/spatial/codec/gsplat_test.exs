defmodule ExCodecs.Spatial.Codec.GsplatTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.{Gaussian, GaussianCloud}
  alias ExCodecs.Spatial.Codec.Gsplat

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
end

defmodule ExCodecs.Spatial.Gaussian do
  @moduledoc """
  A single 3D Gaussian splat used for data interchange, not rendering.

  ## Fields

    * `:position` — `{float(), float(), float()}` center in application-defined
      Cartesian units; required by the struct and defaults to the origin.
    * `:rotation` — `quaternion()` in scalar-first `{w, x, y, z}` order;
      defaults to identity `{1.0, 0.0, 0.0, 0.0}`. Normalization is not enforced.
    * `:scale` — `scale3()` along local axes in the position's units; defaults
      to `{1.0, 1.0, 1.0}`. Positivity is not enforced.
    * `:opacity` — `float()`; defaults to `1.0`, conventionally in `0.0..1.0`.
    * `:color` — `rgb()` linear RGB; defaults to mid-gray
      `{0.5, 0.5, 0.5}`. Components are commonly DC color coefficients.
    * `:sh` — `sh_coeffs()`; defaults to `nil`. Coefficient ordering is
      codec-specific.
    * `:metadata` — `map()` of application data; defaults to `%{}`.

  ## Example

      iex> ExCodecs.Spatial.Gaussian.new({1, 2, 3},
      ...>   rotation: {1, 0, 0, 0},
      ...>   scale: {0.1, 0.2, 0.3},
      ...>   opacity: 0.8,
      ...>   color: {1.0, 0.25, 0.0}
      ...> )
      %ExCodecs.Spatial.Gaussian{
        position: {1.0, 2.0, 3.0},
        rotation: {1.0, 0.0, 0.0, 0.0},
        scale: {0.1, 0.2, 0.3},
        opacity: 0.8,
        color: {1.0, 0.25, 0.0},
        sh: nil,
        metadata: %{}
      }
  """

  @typedoc """
  Linear RGB components `{red, green, blue}`. Values are conventionally
  normalized but no range is enforced. For example, `{1.0, 0.25, 0.0}` is a
  warm orange.
  """
  @type rgb :: {float(), float(), float()}
  @typedoc """
  A scalar-first rotation quaternion `{w, x, y, z}`. Unit length is
  conventional but is not enforced. For example,
  `{1.0, 0.0, 0.0, 0.0}` is the identity rotation.
  """
  @type quaternion :: {float(), float(), float(), float()}
  @typedoc """
  Local-axis Gaussian scales `{sx, sy, sz}` in position units.
  For example, `{0.1, 0.2, 0.05}` describes an anisotropic Gaussian.
  """
  @type scale3 :: {float(), float(), float()}
  @typedoc """
  Codec-specific nested spherical-harmonic coefficient lists, or `nil` when
  no coefficients are present. For example, `[[0.1, 0.2, 0.3]]` stores one
  RGB coefficient group.
  """
  @type sh_coeffs :: [[float()]] | nil

  @typedoc """
  A Gaussian splat. See the module documentation for every field, its default,
  units or conventions, and a construction example.
  """
  @type t :: %__MODULE__{
          position: {float(), float(), float()},
          rotation: quaternion(),
          scale: scale3(),
          opacity: float(),
          color: rgb(),
          sh: sh_coeffs(),
          metadata: map()
        }

  @enforce_keys [:position]
  defstruct position: {0.0, 0.0, 0.0},
            rotation: {1.0, 0.0, 0.0, 0.0},
            scale: {1.0, 1.0, 1.0},
            opacity: 1.0,
            color: {0.5, 0.5, 0.5},
            sh: nil,
            metadata: %{}

  @doc """
  Builds a Gaussian from position and options.

  ## Arguments

    * `position` — `{number(), number(), number()}` center coordinates, stored
      as floats.
    * `opts` — a keyword list with:
      * `:rotation` — numeric `{w, x, y, z}`; defaults to identity.
      * `:scale` — numeric `{sx, sy, sz}`; defaults to `{1.0, 1.0, 1.0}`.
      * `:opacity` — number; defaults to `1.0` and is stored as a float.
      * `:color` — numeric `{r, g, b}`; defaults to `{0.5, 0.5, 0.5}`.
      * `:sh` — `sh_coeffs()`; defaults to `nil`.
      * `:metadata` — `map()`; defaults to `%{}`.

  ## Returns

  `%Gaussian{}`

  ## Raises

  * `FunctionClauseError` for a non-numeric or malformed position, rotation,
    or scale/color tuple, or when `opts` is not a keyword list.
  * `ArithmeticError` if `:opacity` is not numeric.

  ## Examples

      iex> g = ExCodecs.Spatial.Gaussian.new({1.0, 2.0, 3.0}, opacity: 0.5)
      iex> g.position
      {1.0, 2.0, 3.0}
      iex> g.opacity
      0.5
  """
  @spec new({number(), number(), number()}, keyword()) :: t()
  def new({x, y, z}, opts \\ []) when is_number(x) and is_number(y) and is_number(z) do
    %__MODULE__{
      position: {x * 1.0, y * 1.0, z * 1.0},
      rotation: float4(Keyword.get(opts, :rotation, {1.0, 0.0, 0.0, 0.0})),
      scale: float3(Keyword.get(opts, :scale, {1.0, 1.0, 1.0})),
      opacity: Keyword.get(opts, :opacity, 1.0) * 1.0,
      color: float3(Keyword.get(opts, :color, {0.5, 0.5, 0.5})),
      sh: Keyword.get(opts, :sh),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp float3({a, b, c}) when is_number(a) and is_number(b) and is_number(c) do
    {a * 1.0, b * 1.0, c * 1.0}
  end

  defp float4({a, b, c, d})
       when is_number(a) and is_number(b) and is_number(c) and is_number(d) do
    {a * 1.0, b * 1.0, c * 1.0, d * 1.0}
  end
end

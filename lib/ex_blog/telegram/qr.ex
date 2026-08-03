defmodule ExBlog.Telegram.QR do
  @moduledoc "Renders an ExGram login link as a responsive SVG QR code."

  alias QRCode, as: Encoder

  @svg_root ~r/<svg\b[^>]*>/
  @width_attribute ~r/\bwidth="(\d+(?:\.\d+)?)"/
  @height_attribute ~r/\bheight="(\d+(?:\.\d+)?)"/

  @spec render(String.t()) :: {:ok, String.t()} | {:error, term()}
  def render(payload) when is_binary(payload) and byte_size(payload) <= 4_096 do
    if String.trim(payload) == "" do
      {:error, :empty_payload}
    else
      case payload |> Encoder.create(:high) |> Encoder.render(:svg) do
        {:ok, svg} -> {:ok, responsive(svg)}
        {:error, _reason} = error -> error
      end
    end
  end

  def render(_payload), do: {:error, :invalid_payload}

  @doc false
  @spec responsive(String.t()) :: String.t()
  def responsive(svg) when is_binary(svg) do
    with [root] <- Regex.run(@svg_root, svg),
         [_, width] <- Regex.run(@width_attribute, root),
         [_, height] <- Regex.run(@height_attribute, root) do
      responsive_root =
        root
        |> remove_sizing_attributes()
        |> String.replace_suffix(
          ">",
          ~s( viewBox="0 0 #{width} #{height}" width="100%" height="100%" preserveAspectRatio="xMidYMid meet">)
        )

      String.replace(svg, root, responsive_root, global: false)
    else
      _missing_dimensions -> svg
    end
  end

  defp remove_sizing_attributes(root) do
    root
    |> String.replace(~r/\swidth="[^"]*"/, "")
    |> String.replace(~r/\sheight="[^"]*"/, "")
    |> String.replace(~r/\sviewBox="[^"]*"/, "")
    |> String.replace(~r/\spreserveAspectRatio="[^"]*"/, "")
  end
end

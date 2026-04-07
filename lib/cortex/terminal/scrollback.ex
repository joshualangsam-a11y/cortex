defmodule Cortex.Terminal.Scrollback do
  @moduledoc """
  Ring buffer for terminal output history.
  Keeps the last N bytes so reconnecting clients can restore state.
  """

  defstruct [:max_bytes, :buffer, :size]

  @default_max_bytes 256_000

  def new(max_bytes \\ @default_max_bytes) do
    %__MODULE__{
      max_bytes: max_bytes,
      buffer: [],
      size: 0
    }
  end

  def push(%__MODULE__{} = sb, data) when is_binary(data) do
    new_size = sb.size + byte_size(data)
    new_buffer = [data | sb.buffer]

    if new_size > sb.max_bytes do
      trim(%__MODULE__{sb | buffer: new_buffer, size: new_size})
    else
      %__MODULE__{sb | buffer: new_buffer, size: new_size}
    end
  end

  def to_binary(%__MODULE__{buffer: buffer}) do
    buffer
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp trim(%__MODULE__{max_bytes: max_bytes} = sb) do
    binary = to_binary(sb)
    trimmed = binary_part(binary, byte_size(binary) - max_bytes, max_bytes)
    %__MODULE__{sb | buffer: [trimmed], size: max_bytes}
  end
end

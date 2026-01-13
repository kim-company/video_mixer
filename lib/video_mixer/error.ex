defmodule VideoMixer.Error do
  @moduledoc """
  Custom exception used throughout VideoMixer for consistent error reporting.
  """

  defexception [:message, :reason, :context, :details]

  @type t :: %__MODULE__{
          message: String.t(),
          reason: term(),
          context: atom(),
          details: term()
        }

  @impl Exception
  def exception(opts) do
    context = Keyword.get(opts, :context, :unknown)
    reason = Keyword.get(opts, :reason, :unknown)
    details = Keyword.get(opts, :details)
    message = Keyword.get(opts, :message) || build_message(context, reason, details)

    %__MODULE__{
      message: message,
      reason: reason,
      context: context,
      details: details
    }
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  def new(context, reason, details \\ nil) do
    exception(context: context, reason: reason, details: details)
  end

  defp build_message(context, reason, details) do
    base = "VideoMixer error (#{context}): #{format_reason(reason)}"

    case details do
      nil -> base
      _ -> base <> " | details: " <> inspect(details)
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end

defmodule VideoMixer.MixerValidationTest do
  use ExUnit.Case, async: true

  alias VideoMixer.Error
  alias VideoMixer.Frame
  alias VideoMixer.FrameSpec

  test "rejects missing inputs before calling native code" do
    mixer = %VideoMixer{
      ref: make_ref(),
      filter_indexes: [0, 1],
      mapping: [%FrameSpec{accepted_frame_size: 10}, %FrameSpec{accepted_frame_size: 20}],
      input_order: [:a, :b]
    }

    frame = %Frame{size: 10}

    assert {:error, %Error{context: :mix_input_validation, reason: :missing_inputs}} =
             VideoMixer.mix(mixer, a: frame)
  end

  test "rejects incompatible frames before calling native code" do
    mixer = %VideoMixer{
      ref: make_ref(),
      filter_indexes: [0],
      mapping: [%FrameSpec{accepted_frame_size: 10}],
      input_order: [:a]
    }

    frame = %Frame{size: 11}

    assert {:error, %Error{context: :mix_input_validation, reason: :frame_spec_mismatch}} =
             VideoMixer.mix(mixer, a: frame)
  end
end

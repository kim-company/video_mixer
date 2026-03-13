defmodule VideoMixer.FrameQueue.FlushTest do
  use ExUnit.Case, async: true

  alias VideoMixer.Frame
  alias VideoMixer.FrameQueue, as: Queue
  alias VideoMixer.FrameSpec, as: Spec

  test "flush_to_latest on empty queue is a no-op" do
    queue = Queue.new()
    flushed = Queue.flush_to_latest(queue)

    refute Queue.any?(flushed)
    assert Queue.size(flushed) == 0
  end

  test "flush_to_latest with a single frame keeps it" do
    spec = %Spec{accepted_frame_size: 4}
    frame = %Frame{size: 4, pts: 100}

    queue =
      Queue.new()
      |> Queue.push(spec)
      |> Queue.push(frame)

    assert Queue.size(queue) == 1

    flushed = Queue.flush_to_latest(queue)
    assert Queue.size(flushed) == 1

    {entry, _} = Queue.pop!(flushed)
    assert entry.frame.pts == 100
  end

  test "flush_to_latest keeps only the most recent frame" do
    spec = %Spec{accepted_frame_size: 4}

    queue =
      Queue.new()
      |> Queue.push(spec)
      |> Queue.push(%Frame{size: 4, pts: 100})
      |> Queue.push(%Frame{size: 4, pts: 200})
      |> Queue.push(%Frame{size: 4, pts: 300})

    assert Queue.size(queue) == 3

    flushed = Queue.flush_to_latest(queue)
    assert Queue.size(flushed) == 1

    {entry, _} = Queue.pop!(flushed)
    assert entry.frame.pts == 300
  end

  test "flush_to_latest preserves readiness and spec" do
    spec = %Spec{accepted_frame_size: 8}

    queue =
      Queue.new()
      |> Queue.push(spec)
      |> Queue.push(%Frame{size: 8, pts: 10})
      |> Queue.push(%Frame{size: 8, pts: 20})

    flushed = Queue.flush_to_latest(queue)

    assert Queue.ready?(flushed)
    refute Queue.closed?(flushed)
    assert flushed.current_spec == spec
  end

  test "flush_to_latest preserves stream_finished? flag" do
    spec = %Spec{accepted_frame_size: 4}

    queue =
      Queue.new()
      |> Queue.push(spec)
      |> Queue.push(%Frame{size: 4, pts: 1})
      |> Queue.push(%Frame{size: 4, pts: 2})
      |> Queue.push(:end_of_stream)

    assert queue.stream_finished?

    flushed = Queue.flush_to_latest(queue)
    assert flushed.stream_finished?
    assert Queue.size(flushed) == 1

    {entry, remainder} = Queue.pop!(flushed)
    assert entry.frame.pts == 2
    assert Queue.closed?(remainder)
  end
end

# typed: strict
# frozen_string_literal: true

require "pycall"
require "sorbet-runtime"

#  This class handles synchronization between different devices using the Link
#  protocol.
#
#  You can subscribe other objects (i.e. Streams), which will be notified on
#  each clock tick. It expects that subscribers define a `notify_tick` method.
class LinkClock
  extend T::Sig

  sig { returns(T.any(Float, Integer)) }
  attr_accessor :bpm

  sig { params(bpm: T.any(Float, Integer)).void }
  def initialize(bpm = 120)
    link = PyCall.import_module("link")

    @bpm = T.let(bpm, T.any(Float, Integer))

    @link = T.let(link.Link.new(bpm), T.untyped)

    @subscribers = T.let([], T::Array[SuperDirtStream])

    @is_running = T.let(false, T::Boolean)

    @mutex = T.let(Mutex.new, Mutex)

    @notify_thread = T.let(Thread.new {}, Thread)
  end
  # Subscribe an object to recieve tick notifications.
  sig { params(subscriber: SuperDirtStream).void }
  def subscribe(subscriber)
    Thread.new {
      @mutex.synchronize { @subscribers << subscriber }
    }.join
  end

  # Unsubscribe an object from receiving tick notifications.
  sig { params(subscriber: SuperDirtStream).void }
  def unsubscribe(subscriber)
    Thread.new {
      @mutex.synchronize { @subscribers.delete(subscriber) }
    }.join
  end

  # Start the clock.
  sig { void }
  def start
    return if running?

    Thread.new {
      @mutex.synchronize {
        @is_running = true
      }
    }.join

    create_notify_thread
  end

  # Stop the clock.
  sig { void }
  def stop
    Thread.new {
      @mutex.synchronize { @is_running = false }
    }.join

    # block until the start of the next frame
    @notify_thread.join
  end

  # Returns whether the clock is running right now.
  sig { returns(T::Boolean) }
  def running?
    @is_running
  end

  private

  sig { void }
  def create_notify_thread
    @notify_thread = Thread.new {
      notify_thread_target
    }
    @notify_thread.run
  end

  sig { void }
  def notify_thread_target
    puts("Link enabled")
    @link.enabled = true
    @link.startStopSyncEnabled = true

    start = @link.clock.micros
    mill = 1_000_000
    start_beat = @link.captureSessionState.beatAtTime(start, 4)
    puts("start: #{start_beat}")

    ticks = 0

    # rate, bpc and latency should be constructor args
    rate = 1.fdiv(20)
    frame = rate * mill
    bpc = 4

    while running?
      ticks += 1

      logical_now = (start + (ticks * frame)).floor
      logical_next = (start + ((ticks + 1) * frame)).floor

      now = @link.clock.micros

      # wait until start of next frame
      wait = (logical_now - now).fdiv(mill)
      sleep(wait) if wait.positive?

      break unless running?

      session_state = @link.captureSessionState
      cps = (session_state.tempo.fdiv(bpc)).fdiv(60)
      cycle_from = session_state.beatAtTime(logical_now, 0).fdiv(bpc)
      cycle_to = session_state.beatAtTime(logical_next, 0).fdiv(bpc)

      @subscribers.each do |subscriber|
        subscriber.notify_tick([cycle_from, cycle_to], session_state, cps, bpc, mill, now)
      end
    end

    @link.enabled = false
    puts("Link disabled")
  end
end

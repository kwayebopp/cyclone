# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "pycall"
require_relative "../logging"

# A class for sending control pattern messages to SuperDirt
#
# It should be subscribed to a LinkClock instance.
class SuperDirtStream
  extend T::Sig
  include Logging

  sig { returns(Float) }
  attr_accessor :latency

  sig { returns(T.nilable(Cyclone::Pattern)) }
  attr_accessor :pattern

  sig { params(port: Integer, latency: Float).void }
  def initialize(port = 57120, latency = 0.2)
    @liblo = T.let(PyCall.import_module("liblo"), T.untyped)
    @pattern = T.let(nil, T.nilable(Cyclone::Pattern))
    @address = T.let(@liblo.Address.new(port), T.untyped)

    @port = T.let(port, Integer)
    @latency = T.let(latency, Float)
    @is_playing = T.let(true, T::Boolean)
  end

  # Play stream
  sig { returns(T::Boolean) }
  def play
    self.is_playing = true
  end

  #  Stop stream
  sig { returns(T::Boolean) }
  def stop
    self.is_playing = false
  end

  #  Whether the stream is playing right now
  sig { returns(T::Boolean) }
  def playing?
    @is_playing
  end

  sig do 
    params(
      cycle: [Float, Float],
      session_state: T.untyped,
      cps: Float,
      bpc: Integer,
      mill: Integer,
      now: Integer
    ).void
  end
  def notify_tick(cycle, session_state, cps, bpc, mill, now)
    return unless playing? && pattern

    cycle_from, cycle_to = cycle

    begin
      events = T.cast(pattern, Cyclone::Pattern).onsets_only.query.call(Cyclone::TimeSpan.new(cycle_from, cycle_to))
      logger.debug("\n#{events.map(&:value)}") unless events.empty?

      events.each do |event|
        event_whole = T.cast(event.whole, Cyclone::TimeSpan)
        cycle_on = event_whole.start
        cycle_off = event_whole.stop

        logger.debug([cycle_on, cycle_off, bpc].join(" "))
        logger.debug([cycle_on * bpc, cycle_off * bpc].join(" "))

        link_on = session_state.timeAtBeat((cycle_on * bpc).to_f, 0)
        link_off = session_state.timeAtBeat((cycle_off * bpc).to_f, 0)
        delta_secs = (link_off - link_on).fdiv(mill)

        link_secs = now.fdiv(mill)
        liblo_diff = @liblo.time - link_secs
        ticks = link_on.fdiv(mill) + liblo_diff + latency

        value = event.value
        value["cps"] = cps.to_f
        value["cycle"] = cycle_on.to_f
        value["delta"] = delta_secs.to_f

        msg = []
        # msg = [type: \dirt, dirt: ~dirt]

        value.to_a.each do |k, v|
          if k == "s"
            msg << "sound"
          else
            msg << k
          end
          msg << v
        end

        logger.debug(msg.join(" "))
        bundle = liblo.Bundle.new(ticks, liblo.Message.new("/dirt/play", *msg))
        PyCall.getattr(liblo, :send).call(address, bundle)
      end
    rescue Exception => e
      puts e.message
    end
  end

  private

  sig { returns(Integer) }
  attr_reader :port

  sig { returns(T.untyped) }
  attr_reader :address, :liblo

  sig { params(is_playing: T::Boolean).returns(T::Boolean) }
  attr_writer :is_playing
end

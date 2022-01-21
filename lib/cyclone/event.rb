# typed: strict
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"

# `Event` class, representing a value active during the timespan
# `part`. This might be a fragment of an event, in which case the
# timespan will be smaller than the `whole` timespan, otherwise the
# two timespans will be the same. The `part` must never extend outside of the
# `whole`. If the event represents a continuously changing value
# then the `whole` will be returned as `nil`, in which case the given
# value will have been sampled from the point halfway between the
# start and end of the `part` timespan.
module Cyclone
  class Event
    extend T::Sig

    sig { returns(T.nilable(Cyclone::TimeSpan)) }
    attr_accessor :whole
    sig { returns(Cyclone::TimeSpan) }
    attr_accessor :part

    sig { returns(T.untyped) }
    attr_accessor :value

    sig { params(whole: T.nilable(Cyclone::TimeSpan), part: Cyclone::TimeSpan, value: T.untyped).void }
    def initialize(whole, part, value)
      @whole = whole
      @part = part
      @value = value
    end

    sig { returns(T::Boolean) }
    def has_onset?
      whole&.start == part.start
    end

    # Returns a new `Event` with the function fun applied to the event `TimeSpan`s.
    # I'd use a `SpanLambda` here, but need to allow for `nil` for the event `whole`
    sig { params(fun: T.proc.params(span: T.nilable(Cyclone::TimeSpan)).returns(Cyclone::TimeSpan)).returns(Event) }
    def with_span(fun)
      self.class.new(
        whole.nil? ? nil : fun.call(whole),
        fun.call(part),
        value
      )
    end

    # Returns a new `Event` with the function `fun` applies to the event `value`.
    sig { params(fun: T.proc.params(value: T.untyped).returns(T.untyped)).returns(Cyclone::Event) }
    def with_value(fun)
      self.class.new(whole, part, fun.call(value))
    end

    sig { returns(String) }
    def inspect
      "Event(#{whole}, #{part}, #{value.inspect})"
    end
    alias_method :to_s, :inspect
  end
end

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
    ValueLambda = T.type_alias { T.proc.params(value: T.untyped).returns(T.untyped) }


    sig { returns(T.nilable(Cyclone::TimeSpan)) }
    attr_accessor :whole

    sig { returns(Cyclone::TimeSpan) }
    attr_accessor :part

    sig { returns(T.untyped) }
    attr_accessor :value

    sig { params(whole: T.nilable(Cyclone::TimeSpan), part: Cyclone::TimeSpan, value: T.untyped).void }
    def initialize(whole, part, value)
      # raise an error if `part` is not contained within `whole`
      unless whole.nil? || whole.include?(part)
        raise ArgumentError, "part (#{part}) must be smaller than or equal to whole #{(whole)}"
      end

      @whole = whole
      @part = part
      @value = value
    end

    sig { returns(T::Boolean) }
    def has_onset?
      whole&.start == part.start
    end

    # Returns a new `Event` with the function fun applied to the event `TimeSpan`s.
    sig { params(fun: TimeSpan::SpanLambda).returns(Event) }
    def with_span(fun)
      self.class.new(
        whole.nil? ? nil : fun.call(whole),
        fun.call(part),
        value
      )
    end

    # Returns a new `Event` with the function `fun` applies to the event `value`.
    sig { params(fun: ValueLambda).returns(Cyclone::Event) }
    def with_value(fun)
      self.class.new(whole, part, fun.call(value))
    end
    alias fmap with_value

    sig { returns(String) }
    def inspect
      "Event(#{whole}, #{part}, #{value.inspect})"
    end
    alias_method :to_s, :inspect
  end
end

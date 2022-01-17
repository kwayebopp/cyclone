# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Extends the `Rational < Numeric` class to support operations
# needed by `Cyclone` and its subclasses
class Rational
  extend T::Sig

  #  Returns the start of the cycle.
  sig { returns(Rational) }
  def sample
    Rational(floor)
  end

  # Returns the start of the next cycle.
  sig { returns(Rational) }
  def next_sample
    sample + 1
  end

  # Returns a TimeSpan representing the begin and end of the Time value's cycle
  sig { returns(Cyclone::TimeSpan) }
  def whole_cycle
    Cyclone::TimeSpan.new(sample, next_sample)
  end
end

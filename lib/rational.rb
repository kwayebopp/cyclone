# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

class Rational
  extend T::Sig

  #  The start of the cycle that a given time value is in
  sig { returns(Rational) }
  def sample
    Rational(floor)
  end

  # The start of the next cycle
  sig { returns(Rational) }
  def next_sample
    sample + 1
  end

  sig { returns(Cyclone::TimeSpan) }
  def whole_cycle
    Cyclone::TimeSpan.new(sample, next_sample)
  end
end

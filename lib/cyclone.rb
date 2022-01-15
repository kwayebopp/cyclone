# typed: ignore
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "cyclone/version"

module Cyclone
  extend T::Sig
  Span = T.type_alias { [Rational, Rational] }
  PatternQuery = T.type_alias { T.proc.params(b: Rational, e: Rational).returns(T.untyped) }

  include Kernel

  class Error < StandardError; end

  module_function

  #  The start of the cycle that a given time value is in
  sig { params(t: Rational).returns(Rational) }
  def sample(t)
    Rational(t.floor)
  end

  # The start of the next cycle
  sig { params(t: Rational).returns(Rational) }
  def next_sample(t)
    sample(t) + 1
  end

  sig { params(t: Rational).returns(Span) }
  def whole_cycle(t)
    [sample(t), next_sample(t)]
  end

  # Splits a timespan at cycle boundaries
  sig { params(b: Rational, e: Rational).returns(T::Array[Span]) }
  def span_cycles(b, e)
    return [] if e <= b
    return [[b, e]] if sample(b) == sample(e)

    next_b = next_sample(b)
    spans = span_cycles(next_b, e)
    spans.unshift([b, next_b])
  end

  # flatten list of lists
  sig { params(cycles: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
  def concat(cycles)
    cycles.flatten
  end

  # Fundamental patterns

  sig { returns(Pattern) }
  def silence
    Pattern.new(T.let(->(_b, _e) { [] }, PatternQuery))
  end

  # Repeat discrete value once per cycle
  sig { params(value: T.untyped).returns(Pattern) }
  def atom(value)
    query = lambda do |b, e|
      span_cycles(b, e).map { |span| [whole_cycle(span[0]), span, value] }
    end

    Pattern.new(query)
  end

  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def slowcat(patterns)
    query = lambda do |b, e|
      pattern = patterns[b.floor % patterns.size]
      T.must(pattern).query.call(b, e)
    end
    pattern = Pattern.new(query)
    pattern.split_queries
  end

  class Pattern
    extend T::Sig
    sig { returns(PatternQuery) }
    attr_accessor :query

    sig { params(query: PatternQuery).void }
    def initialize(query)
      @query = query
    end

    sig { returns(Pattern) }
    def split_queries
      query = T.let(
        lambda do |b, e|
          Cyclone.span_cycles(b, e).map { |span| self.query.call(span[0], span[1]) }
        end,
        PatternQuery
      )

      Pattern.new(query)
    end
  end
end

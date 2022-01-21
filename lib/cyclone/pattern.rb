# typed: true
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"

module Cyclone
  # `Pattern` class, representing discrete and continuous `Event`s as a
  # function of time.
  class Pattern
    extend T::Sig
    Query = T.type_alias { T.proc.params(span: TimeSpan).returns(T::Array[Event]) }

    sig { returns(Query) }
    attr_accessor :query

    sig { params(query: Query).void }
    def initialize(query)
      @query = query
    end

    # Splits queries at cycle boundaries. Makes some calculations easier
    # to express, as everything then happens within a cycle.
    sig { returns(Pattern) }
    def split_queries
      query = lambda do |span|
        span.span_cycles.flat_map(&self.query)
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to the `TimeSpan` of the query.
    sig { params(span_lambda: TimeSpan::SpanLambda).returns(Pattern) }
    def with_query_span(span_lambda)
      query = lambda do |span|
        self.query.call(span_lambda.call(span))
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of the the query `TimeSpan`.
    sig { params(time_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_query_time(time_lambda)
      query = lambda do |span|
        self.query.call(span.with_time(time_lambda))
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to each `Event`
    # timespan.
    sig { params(fun: T.proc.params(span: T.nilable(TimeSpan)).returns(TimeSpan)).returns(Pattern) }
    def with_event_span(fun)
      query = lambda do |span|
        self.query.call(span).map { |event| event.with_span(fun) }
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of each event `TimeSpan`.
    sig { params(time_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_event_time(time_lambda)
      with_event_span(->(span) { span.with_time(time_lambda) })
    end

    # Returns a new `Pattern`, with the function applied to the value of
    # each `Event`. It has the alias 'fmap'
    sig { params(fun: T.proc.params(value: T.untyped).returns(T.untyped)).returns(Pattern) }
    def with_value(fun)
      query = lambda do |span|
        self.query.call(span).map { |event| event.with_value(fun) }
      end

      self.class.new(query)
    end
    alias_method :fmap, :with_value

    # Returns a new pattern that will only return events where the start
    # of the 'whole' timespan matches the start of the 'part'
    # timespan, i.e. the events that include their 'onset'
    sig { returns(Pattern) }
    def onsets_only
      query = lambda do |span|
        self.query.call(span).select(&:has_onset?)
      end

      self.class.new(query)
    end

    # Speeds up a `Pattern` by the given `factor``
    sig { params(factor: Numeric).returns(Pattern) }
    def _fast(factor)
      fast_query = with_query_time(->(t) { t * factor })
      fast_query.with_event_time(->(t) { t / factor })
    end

    # Speeds up a `Pattern` using the given `pattern_of_factors`.
    sig { params(pattern_of_factors: Pattern).returns(Pattern) }
    def fast(pattern_of_factors)
      pattern_of_factors.fmap(->(factor) { _fast(factor) }).outer_join
    end

    # Slow slows down a `Pattern` by the given `factor`
    sig { params(factor: Numeric).returns(Pattern) }
    def slow(factor)
      _fast(1 / factor.to_f)
    end

    # Equivalent of Tidal's `<~` operator
    sig { params(offset: Numeric).returns(Pattern) }
    def early(offset)
      with_query_time(->(t) { t + offset }).with_event_time(->(t) { t - offset })
    end

    # Equivalent of Tidal's `~>` operator
    sig { params(offset: Numeric).returns(Pattern) }
    def late(offset)
      early(-offset)
    end

    sig { returns(T::Array[Event]) }
    def first_cycle
      query.call(TimeSpan.new(0, 1))
    end

    sig { params(thing: T.untyped).returns(Pattern) }
    def self.reify(thing)
      return thing if thing.instance_of?(Pattern)

      Cyclone.pure(thing)
    end

    # Tidal's `<*>` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def app(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return this.intersect(that) unless this.nil? || that.nil?
      end

      _app_whole(whole_fun, pattern_of_vals)
    end

    # Tidal's `<*` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def appl(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return this unless this.nil? || that.nil?
      end

      _app_whole(whole_fun, pattern_of_vals)
    end

    # Tidal's `*>` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def appr(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return that unless this.nil? || that.nil?
      end

      _app_whole(whole_fun, pattern_of_vals)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def bind(fun)
      whole_fun = lambda do |this, that|
        return this.intersect(that) unless this.nil? || that.nil?
      end
      _bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    # the intersection of matched inner and outer events.
    sig { returns(Pattern) }
    def join
      bind(Cyclone.id)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def inner_bind(fun)
      whole_fun = lambda do |this, that|
        return this unless this.nil? || that.nil?
      end
      _bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    # taken from inner events.
    sig { returns(Pattern) }
    def inner_join
      inner_bind(Cyclone.id)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def outer_bind(fun)
      whole_fun = lambda do |this, that|
        return that unless this.nil? || that.nil?
      end
      _bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    #  taken from outer events.
    sig { returns(Pattern) }
    def outer_join
      outer_bind(Cyclone.id)
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def +(other)
      fmap(->(x) { ->(y) { x + y } }).app(self.class.reify(other))
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def ladd(other)
      # fmap(->(x) { ->(y) { x + y } }).app(reify(other))
      self.+(other)
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def radd(other)
      # fmap(->(x) { ->(y) { y + x } }).app(reify(other))
      self.+(other)
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def -(other)
      fmap(->(x) { ->(y) { x - y } }).app(self.class.reify(other))
    end

    sig { params(other: T.untyped).void }
    def rsub(other)
      raise NotImplementedError
    end

    # The union of two patterns of dictionaries, with values from left
    # replacing any with the same name from the right
    sig { params(other: Pattern).returns(Pattern) }
    def <<(other)
      fmap(->(x) { ->(y) { {**y, **x} } }).app(other)
    end

    # The union of two patterns of dictionaries, with values from right
    # replacing any with the same name from the left
    sig { params(other: Pattern).returns(Pattern) }
    def >>(other)
      fmap(->(x) { ->(y) { {**x, **y} } }).app(other)
    end

    def inspect
      query.call(TimeSpan.new(0, 1)).inspect
    end

    private

    # Assumes self is a pattern of functions, and given a function to
    # resolve wholes, applies a given pattern of values to that pattern
    # of functions.
    sig do
      params(
        whole_fun: T.proc.params(
          arg0: TimeSpan,
          arg1: TimeSpan
        ).returns(T.nilable(TimeSpan)),
        pattern_of_vals: Pattern
      ).returns(Pattern)
    end
    def _app_whole(whole_fun, pattern_of_vals)
      pattern_of_funs = self
      query = lambda do |span|
        event_funs = pattern_of_funs.query.call(span)
        event_vals = pattern_of_vals.query.call(span)
        apply = lambda do |event_fun, event_val|
          intersection = event_fun.part.maybe_intersect(event_val.part)
          unless intersection.nil?
            Event.new(
              whole_fun.call(event_fun.whole, event_val.whole),
              intersection,
              event_fun.value.call(event_val.value)
            )
          end
        end
        event_funs.flat_map do |event_fun|
          # .compact to eliminate `nil`s that may be returned from `apply`
          event_vals.map { |event_val| apply.call(event_fun, event_val) }.compact
        end
      end
      self.class.new(query)
    end

    sig do
      params(
        choose_whole: T.proc.params(
          this_event: Event,
          that_event: Event
        ).returns(T.nilable(TimeSpan)),
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def _bind_whole(choose_whole, fun)
      pattern_of_values = self
      query = lambda do |span|
        with_whole = lambda do |this_event, that_event|
          Event.new(
            choose_whole.call(this_event.whole, that_event.whole),
            that_event.part,
            that_event.value
          )
        end
        match = lambda do |event|
          fun.call(event.value).query.call(event.part).map do |evt|
            with_whole.call(event, evt)
          end
        end
        pattern_of_values.query.call(span).flat_map(&match)
      end

      self.class.new(query)
    end
  end
end

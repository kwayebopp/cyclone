# typed: true
# frozen_string_literal: true

require "test_helper"

class CycloneTest < Minitest::Test
  def multi_list
    [(1..3).to_a, (4..6).to_a]
  end

  def test_that_it_has_a_version_number
    refute_nil ::Cyclone::VERSION
  end

  def test_concat
    flat_list = Cyclone.concat(multi_list)
    assert flat_list == [1, 2, 3, 4, 5, 6]
  end
end

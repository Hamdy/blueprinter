# frozen_string_literal: true

require 'activerecord_helper'
require 'benchmark_helper'
require 'blueprinter'

class Blueprinter::ActiveRecordIPSTest < Minitest::Test
  include FactoryBot::Syntax::Methods
  include BenchmarkHelper

  def setup
    @blueprinter = Class.new(Blueprinter::Base) do
      fields :first_name, :last_name
    end
    @prepared_objects = 10.times.map {create(:user)}
  end

  def test_render
    # Informational only: wall-clock IPS is machine dependent and is never asserted against an
    # absolute threshold (see IPSTest for why).
    puts "\nActiveRecord IPS: #{iterate { @blueprinter.render(@prepared_objects) }}"

    # Regression guard: rendering must allocate O(objects), not O(objects * fields). Deterministic
    # and machine independent -- tripling the collection must at most triple the allocations.
    small = allocations { @blueprinter.render(@prepared_objects) }
    large = allocations { @blueprinter.render(@prepared_objects * 3) }

    assert_operator large, :<=, (small * 3) + 5,
                     "Render allocations grew super-linearly (#{small} -> #{large} for 3x the " \
                     'objects); a per-object or per-field allocation regression likely crept in.'
  end
end

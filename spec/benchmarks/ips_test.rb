# frozen_string_literal: true

require 'benchmark_helper'
require 'blueprinter'
require 'ostruct'

class Blueprinter::IPSTest < Minitest::Test
  include BenchmarkHelper

  def setup
    @blueprinter = Class.new(Blueprinter::Base) do
      transformer = Class.new(Blueprinter::Transformer) do
        define_method :transform do |result_hash, _obj, _options|
          {
            foo: :bar,
            **result_hash
          }
        end
      end

      field :id
      field :name

      transform transformer
    end
    @prepared_objects = 10.times.map {|i| OpenStruct.new(id: i, name: "obj #{i}")}
  end

  def test_render
    # Informational only: wall-clock IPS is machine dependent, so it is printed but never asserted
    # against an absolute threshold (an absolute threshold has so much slack on a fast machine that
    # it cannot catch a regression -- e.g. this suite did not catch a ~25% render regression).
    puts "\nBasic IPS: #{iterate { @blueprinter.render(@prepared_objects) }}"

    # Regression guard: rendering must allocate O(objects), not O(objects * fields). Deterministic
    # and machine independent -- tripling the collection must at most triple the allocations.
    small = allocations { @blueprinter.render(@prepared_objects) }
    large = allocations { @blueprinter.render(@prepared_objects * 3) }

    assert_operator large, :<=, (small * 3) + 5,
                     "Render allocations grew super-linearly (#{small} -> #{large} for 3x the " \
                     'objects); a per-object or per-field allocation regression likely crept in.'
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/benchmark'

module BenchmarkHelper
  def iterate
    start = Time.now
    count = 0
    while Time.now - start <= 1 do
      yield
      count += 1
    end
    count
  end

  # Counts the objects allocated while running the block, with GC paused so the count is stable.
  #
  # Unlike wall-clock IPS (which varies too much between machines to threshold meaningfully, and so
  # cannot catch a regression), the allocation count is deterministic and machine independent. It is
  # the right basis for a regression assertion -- a per-field or per-object allocation regression
  # (exactly the class of bug that went unnoticed before) changes this number, a slow CI runner does
  # not.
  def allocations
    GC.start
    GC.disable
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  ensure
    GC.enable
  end
end

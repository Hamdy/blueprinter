# frozen_string_literal: true

class MockField
  attr_reader :name, :method

  def initialize(method, name = nil)
    @method = method
    @name = name || method
  end

  # Mirrors Field#compile's simple path: a closure that writes the extracted value into the hash.
  # ViewCollection compiles every field while building its cache.
  def compile
    name = @name
    method = @method
    lambda do |result_hash, object, _options|
      result_hash[name] = object.is_a?(Hash) ? object[method] : object.public_send(method)
    end
  end
end

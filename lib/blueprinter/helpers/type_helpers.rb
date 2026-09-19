# frozen_string_literal: true

module Blueprinter
  module TypeHelpers
    private

    def array_like?(object)
      # Fast path: Array is always array-like and is the overwhelmingly common collection, so short
      # circuit before touching global configuration or iterating the configured classes.
      return true if object.is_a?(Array)

      Blueprinter.configuration.array_like_classes.any? do |klass|
        object.is_a?(klass)
      end
    end
  end
end

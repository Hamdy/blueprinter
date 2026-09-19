# frozen_string_literal: true

require 'json'
require 'blueprinter/extensions'
require 'blueprinter/extractors/auto_extractor'

module Blueprinter
  class Configuration
    # Attributes baked into a Blueprint's compiled render pipeline (see Field#compile) or into
    # ViewCollection's cache. Mutating one of these must bump the generation counter, otherwise
    # those caches keep serving behaviour derived from the previous configuration.
    COMPILED_ATTRIBUTES = %i[
      custom_array_like_classes
      datetime_format
      default_transformers
      field_default
      if
      sort_fields_by
      unless
    ].freeze

    # Attributes re-read on every render, so they need no cache invalidation.
    LIVE_ATTRIBUTES = %i[
      association_default
      deprecations
      generator
      method
    ].freeze

    VALID_CALLABLES = %i[if unless].freeze

    # Monotonic counter, deliberately class-level rather than per-instance: reset_configuration!
    # installs a brand new Configuration, and an instance counter would restart at zero, making a
    # cache built against the previous instance look current.
    #
    # Mutating configuration is a boot-time activity, so this is intentionally lock-free. A torn
    # read can only delay a recompile by one render, never produce a corrupt cache -- ViewCollection
    # serialises the rebuild itself.
    @generation = 0

    class << self
      attr_reader :generation

      def bump_generation!
        @generation += 1
      end
    end

    attr_accessor(*LIVE_ATTRIBUTES)
    attr_reader(*COMPILED_ATTRIBUTES, :extensions, :extractor_default)

    # Writers for compiled attributes invalidate dependent caches. Defined after the attr_reader
    # calls above so these take precedence.
    COMPILED_ATTRIBUTES.each do |attribute|
      define_method(:"#{attribute}=") do |value|
        instance_variable_set(:"@#{attribute}", value)
        invalidate_compiled!
        value
      end
    end

    def initialize
      @association_default = nil
      @custom_array_like_classes = []
      @datetime_format = nil
      @default_transformers = []
      @deprecations = :stderror
      @extensions = Extensions.new
      @extractor_default = AutoExtractor
      @field_default = nil
      @generator = JSON
      @if = nil
      @method = :generate
      @sort_fields_by = :name_asc
      @unless = nil
    end

    def extensions=(list)
      @extensions = Extensions.new(list)
    end

    def array_like_classes
      @_array_like_classes ||= [
        Array,
        defined?(ActiveRecord::Relation) && ActiveRecord::Relation,
        *custom_array_like_classes
      ].compact
    end

    def jsonify(blob)
      generator.public_send(method, blob)
    end

    def valid_callable?(callable_name)
      VALID_CALLABLES.include?(callable_name)
    end

    # @param extractor [Class<Blueprinter::AutoExtractor>]
    def extractor_default=(extractor)
      reset_default_extractor!

      @extractor_default = extractor
      invalidate_compiled!
    end

    # @return [Blueprinter::AutoExtractor]
    def default_extractor
      @_default_extractor ||= extractor_default.new
    end

    private

    # Drops memoised values derived from configuration, and signals every ViewCollection to
    # recompile on next use.
    def invalidate_compiled!
      @_array_like_classes = nil
      self.class.bump_generation!
    end

    def reset_default_extractor!
      @_default_extractor = nil
    end
  end
end

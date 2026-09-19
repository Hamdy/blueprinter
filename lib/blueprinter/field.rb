# frozen_string_literal: true

require 'blueprinter/extractors/auto_extractor'

# @api private
module Blueprinter
  class Field
    attr_reader :method, :name, :extractor, :options, :blueprint

    def initialize(method, name, extractor, blueprint, options = {})
      @method = method
      @name = name
      @extractor = extractor
      @blueprint = blueprint
      @options = options
    end

    def extract(object, local_options)
      extractor.extract(method, object, local_options, options)
    end

    def skip?(field_name, object, local_options)
      resolve_callables!
      return true if @_if_callable && !@_if_callable.call(field_name, object, local_options)

      @_unless_callable && @_unless_callable.call(field_name, object, local_options)
    end

    # Compiles this field into a closure that writes its rendered value into a result hash.
    #
    # ViewCollection calls this once per field while building its cache, so the per-field decisions
    # -- which extractor applies, whether a datetime format is in play, whether a default is
    # configured, whether :if/:unless conditions exist -- are resolved a single time instead of
    # being re-derived for every object in a collection.
    #
    # @return [Proc] called with (result_hash, object, options)
    def compile
      simple? ? compile_simple : compile_general
    end

    private

    # The overwhelmingly common field: read an attribute (or Hash key) and store it. With no
    # conditions, block, datetime format or default in play, none of AutoExtractor's per-call
    # branching is needed.
    def compile_simple
      name = @name
      method = @method

      lambda do |result_hash, object, _options|
        result_hash[name] = object.is_a?(Hash) ? object[method] : object.public_send(method)
      end
    end

    # Everything else keeps today's behaviour, going through the configured extractor.
    def compile_general
      name = @name
      exclude_if_nil = options[:exclude_if_nil]

      lambda do |result_hash, object, options_hash|
        next if skip?(name, object, options_hash)

        value = extract(object, options_hash)
        next if value.nil? && exclude_if_nil

        result_hash[name] = value
      end
    end

    # Whether this field can take the fast path. Associations never qualify: their extractor is an
    # AssociationExtractor, which recurses into another Blueprint.
    def simple?
      extractor.instance_of?(AutoExtractor) && plain_options? && plain_configuration?
    end

    def plain_options?
      !options[:block] && !options[:exclude_if_nil] && !options[:datetime_format] &&
        !options.key?(:default) && !options.key?(:default_if)
    end

    # A global datetime_format or field_default changes the value of every field, and a global
    # :if/:unless adds a per-object condition, so none of those can be skipped.
    def plain_configuration?
      config = Blueprinter.configuration

      config.datetime_format.nil? && config.field_default.nil? && !if_callable && !unless_callable
    end

    def if_callable
      resolve_callables!
      @_if_callable
    end

    def unless_callable
      resolve_callables!
      @_unless_callable
    end

    # Resolves both conditions once, then reuses them.
    #
    # NOTE: `callable_from` returns `false` when no callable is configured, which is the common
    # case, so `||=` would never memoize and would re-resolve -- including a global configuration
    # lookup -- for every field of every object rendered.
    #
    # Keyed on Configuration.generation so that mutating global `config.if`/`config.unless` still
    # takes effect, while costing only an integer comparison on the hot path. Fields on the fast
    # path never reach here at all, since their closure captures no condition.
    def resolve_callables!
      generation = Configuration.generation
      return if @_callable_generation == generation

      @_if_callable = callable_from(:if)
      @_unless_callable = callable_from(:unless)
      @_callable_generation = generation
    end

    def callable_from(condition)
      config = Blueprinter.configuration

      # Use field-level callable, or when not defined, try global callable
      tmp = if options.key?(condition)
              options.fetch(condition)
            elsif config.valid_callable?(condition)
              config.public_send(condition)
            end

      return false unless tmp

      case tmp
      when Proc then tmp
      when Symbol then blueprint.method(tmp)
      else
        raise ArgumentError, "#{tmp.class} is passed to :#{condition}"
      end
    end
  end
end

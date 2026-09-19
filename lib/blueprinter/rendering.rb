# frozen_string_literal: true

require 'blueprinter/errors/invalid_root'
require 'blueprinter/errors/meta_requires_root'
require 'blueprinter/errors/unknown_view'
require 'blueprinter/deprecation'

module Blueprinter
  # Encapsulates the rendering logic for Blueprinter.
  module Rendering
    include TypeHelpers

    # Keys consumed by render itself rather than passed through to fields as local options.
    RESERVED_OPTIONS = %i[view root meta].freeze

    # Generates a JSON formatted String represantation of the provided object.
    #
    # @param object [Object] the Object to serialize.
    # @param options [Hash] the options hash which requires a :view. Any
    #   additional key value pairs will be exposed during serialization.
    # @option options [Symbol] :view Defaults to :default.
    #   The view name that corresponds to the group of
    #   fields to be serialized.
    # @option options [Symbol|String] :root Defaults to nil.
    #   Render the json/hash with a root key if provided.
    # @option options [Any] :meta Defaults to nil.
    #   Render the json/hash with a meta attribute with provided value
    #   if both root and meta keys are provided in the options hash.
    #
    # @example Generating JSON with an extended view
    #   post = Post.all
    #   Blueprinter::Base.render post, view: :extended
    #   # => "[{\"id\":1,\"title\":\"Hello\"},{\"id\":2,\"title\":\"My Day\"}]"
    #
    # @return [String] JSON formatted String
    def render(object, options = {})
      jsonify(build_result(object:, options:))
    end

    # Generates a Hash representation of the provided object.
    # Takes a required object and an optional view.
    #
    # @param object [Object] the Object to serialize upon.
    # @param options [Hash] the options hash which requires a :view. Any
    #   additional key value pairs will be exposed during serialization.
    # @option options [Symbol] :view Defaults to :default.
    #   The view name that corresponds to the group of
    #   fields to be serialized.
    # @option options [Symbol|String] :root Defaults to nil.
    #   Render the json/hash with a root key if provided.
    # @option options [Any] :meta Defaults to nil.
    #   Render the json/hash with a meta attribute with provided value
    #   if both root and meta keys are provided in the options hash.
    #
    # @example Generating a hash with an extended view
    #   post = Post.all
    #   Blueprinter::Base.render_as_hash post, view: :extended
    #   # => [{id:1, title: Hello},{id:2, title: My Day}]
    #
    # @return [Hash]
    def render_as_hash(object, options = {})
      build_result(object:, options:)
    end

    # Generates a JSONified hash.
    # Takes a required object and an optional view.
    #
    # @param object [Object] the Object to serialize upon.
    # @param options [Hash] the options hash which requires a :view. Any
    #   additional key value pairs will be exposed during serialization.
    # @option options [Symbol] :view Defaults to :default.
    #   The view name that corresponds to the group of
    #   fields to be serialized.
    # @option options [Symbol|String] :root Defaults to nil.
    #   Render the json/hash with a root key if provided.
    # @option options [Any] :meta Defaults to nil.
    #   Render the json/hash with a meta attribute with provided value
    #   if both root and meta keys are provided in the options hash.
    #
    # @example Generating a hash with an extended view
    #   post = Post.all
    #   Blueprinter::Base.render_as_json post, view: :extended
    #   # => [{"id" => "1", "title" => "Hello"},{"id" => "2", "title" => "My Day"}]
    #
    # @return [Hash]
    def render_as_json(object, options = {})
      build_result(object:, options:).as_json
    end

    # Converts an object into a Hash representation based on provided view.
    #
    # @param object [Object] the Object to convert into a Hash.
    # @param view_name [Symbol] the view
    # @param local_options [Hash] the options hash which requires a :view. Any
    #   additional key value pairs will be exposed during serialization.
    # @return [Hash]
    def hashify(object, view_name:, local_options:)
      raise Errors::UnknownView, "View '#{view_name}' is not defined" unless view_collection.view?(view_name)

      object = Blueprinter.configuration.extensions.pre_render(object, self, view_name, local_options)
      prepare_data(object, view_name, local_options)
    end

    # @deprecated This method is no longer supported, and was not originally intended to be public. This will be removed
    #   in the next minor release. If similar functionality is needed, use `.render_as_hash` instead.
    #
    # This is the magic method that converts complex objects into a simple hash
    # ready for JSON conversion.
    #
    # Note: we accept view (public interface) that is in reality a view_name,
    # so we rename it for clarity
    #
    # @api private
    def prepare(object, view_name:, local_options:)
      Blueprinter::Deprecation.report(
        <<~MESSAGE
          The `prepare` method is no longer supported will be removed in the next minor release.
          If similar functionality is needed, use `.render_as_hash` instead.
        MESSAGE
      )
      render_as_hash(object, view_name:, local_options:)
    end

    private

    attr_reader :blueprint, :options

    def prepare_data(object, view_name, local_options)
      # Since we're currently providing the current view in the local_options hash when we extract fields, we can merge
      # it in ahead of time to avoid allocating a new hash for every field extraction. When there are no local options
      # (the common case), build the single-entry hash directly rather than paying for Hash#merge.
      local_options_with_view =
        local_options.empty? ? { view: view_name } : local_options.merge(view: view_name)

      # Loop invariants: the compiled render closures and transformers for this view are identical
      # for every object in a collection, so resolve them once here rather than per object.
      compiled_fields = view_collection.compiled_fields_for(view_name)
      transformers = view_collection.transformers(view_name)

      if array_like?(object)
        object.map do |obj|
          object_to_hash(obj, compiled_fields:, transformers:, local_options: local_options_with_view)
        end
      else
        object_to_hash(object, compiled_fields:, transformers:, local_options: local_options_with_view)
      end
    end

    def object_to_hash(object, compiled_fields:, transformers:, local_options:)
      result_hash = {}

      compiled_fields.each { |render_field| render_field.call(result_hash, object, local_options) }
      transformers.each { |transformer| transformer.transform(result_hash, object, local_options) }

      result_hash
    end

    # Strips the keys render consumes, leaving only the local options passed through to fields.
    # Returns the hash untouched when there is nothing to strip (the common no-options render),
    # avoiding a throwaway Hash#except allocation.
    def local_options_from(options)
      return options if options.empty?

      options.except(*RESERVED_OPTIONS)
    end

    def jsonify(data)
      Blueprinter.configuration.jsonify(data)
    end

    def apply_root_key(object:, root:)
      return object unless root
      return { root => object } if root.is_a?(String) || root.is_a?(Symbol)

      raise(Errors::InvalidRoot)
    end

    def add_metadata(object:, metadata:, root:)
      return object unless metadata
      return object.merge(meta: metadata) if root

      raise(Errors::MetaRequiresRoot)
    end

    def build_result(object:, options:)
      view_name = options[:view] || :default

      prepared_object = hashify(
        object,
        view_name:,
        local_options: local_options_from(options)
      )
      object_with_root = apply_root_key(
        object: prepared_object,
        root: options[:root]
      )
      add_metadata(
        object: object_with_root,
        metadata: options[:meta],
        root: options[:root]
      )
    end
  end
end

# frozen_string_literal: true

# Required explicitly so this file is runnable on its own. `require 'blueprinter'` only autoloads
# Base, so Field/AutoExtractor otherwise resolve just by load-order luck from the full suite.
require 'blueprinter/base'
require 'blueprinter/field'
require 'blueprinter/extractors/auto_extractor'

describe '::Field' do
  let(:blueprint) { Class.new(Blueprinter::Base) }
  let(:extractor) { Blueprinter::AutoExtractor.new }
  let(:object) { Struct.new(:first_name).new('Meg') }

  def field(options = {})
    Blueprinter::Field.new(:first_name, :first_name, extractor, blueprint, options)
  end

  describe '#skip?' do
    context 'when no :if/:unless is configured' do
      it 'does not skip the field' do
        expect(field.skip?(:first_name, object, {})).to be_falsey
      end

      # Regression guard. `callable_from` returns `false` in this (very common) case, so the previous
      # `@_if_callable ||= callable_from(:if)` memoization never took hold and re-resolved the
      # callable -- including a global config lookup -- on every field of every rendered object.
      # This accounted for ~25% of total render wall time.
      it 'resolves each condition exactly once, even though resolution returns false' do
        subject = field
        allow(subject).to receive(:callable_from).and_call_original

        5.times { subject.skip?(:first_name, object, {}) }

        expect(subject).to have_received(:callable_from).with(:if).once
        expect(subject).to have_received(:callable_from).with(:unless).once
      end

      it 'memoizes the falsey result rather than leaving the ivar undefined' do
        subject = field
        subject.skip?(:first_name, object, {})

        expect(subject.instance_variable_defined?(:@_if_callable)).to be(true)
        expect(subject.instance_variable_defined?(:@_unless_callable)).to be(true)
        expect(subject.instance_variable_get(:@_if_callable)).to be(false)
      end

      it 'does not read global configuration again after the first call' do
        subject = field
        subject.skip?(:first_name, object, {})

        # Any further global reads would mean resolution is still happening per call.
        expect(Blueprinter).not_to receive(:configuration)
        subject.skip?(:first_name, object, {})
      end
    end

    context 'with a field-level :if proc' do
      it 'skips when the proc returns false' do
        subject = field(if: ->(_name, _object, _opts) { false })
        expect(subject.skip?(:first_name, object, {})).to be(true)
      end

      it 'does not skip when the proc returns true' do
        subject = field(if: ->(_name, _object, _opts) { true })
        expect(subject.skip?(:first_name, object, {})).to be_falsey
      end

      it 'passes the field name, object and options through on every call' do
        seen = []
        subject = field(if: ->(name, obj, opts) { seen << [name, obj, opts] and true })

        subject.skip?(:first_name, object, { foo: :bar })
        subject.skip?(:first_name, object, { foo: :baz })

        expect(seen).to eq([[:first_name, object, { foo: :bar }], [:first_name, object, { foo: :baz }]])
      end

      it 'memoizes the proc itself, calling it once per skip? invocation' do
        calls = 0
        subject = field(if: ->(_name, _object, _opts) { calls += 1 and true })

        3.times { subject.skip?(:first_name, object, {}) }

        expect(calls).to eq(3)
      end
    end

    context 'with a field-level :unless proc' do
      it 'skips when the proc returns true' do
        subject = field(unless: ->(_name, _object, _opts) { true })
        expect(subject.skip?(:first_name, object, {})).to be(true)
      end

      it 'does not skip when the proc returns false' do
        subject = field(unless: ->(_name, _object, _opts) { false })
        expect(subject.skip?(:first_name, object, {})).to be_falsey
      end
    end

    context 'with a symbol referring to a blueprint method' do
      let(:blueprint) do
        Class.new(Blueprinter::Base) do
          def self.render_it?(_name, _object, _opts) = false
        end
      end

      it 'resolves the symbol against the blueprint and skips accordingly' do
        expect(field(if: :render_it?).skip?(:first_name, object, {})).to be(true)
      end

      it 'resolves the symbol only once across repeated calls' do
        subject = field(if: :render_it?)
        expect(blueprint).to receive(:method).with(:render_it?).once.and_call_original

        3.times { subject.skip?(:first_name, object, {}) }
      end
    end

    context 'with an invalid condition type' do
      it 'raises ArgumentError' do
        expect { field(if: 'a string').skip?(:first_name, object, {}) }
          .to raise_error(ArgumentError, /String is passed to :if/)
      end
    end

    context 'with global configuration' do
      after { reset_blueprinter_config! }

      it 'honours a global :if set before first use' do
        Blueprinter.configure { |config| config.if = ->(_name, _object, _opts) { false } }
        expect(field.skip?(:first_name, object, {})).to be(true)
      end

      it 'honours a global :unless set before first use' do
        Blueprinter.configure { |config| config.unless = ->(_name, _object, _opts) { true } }
        expect(field.skip?(:first_name, object, {})).to be(true)
      end

      it 'prefers a field-level condition over the global one' do
        Blueprinter.configure { |config| config.if = ->(_name, _object, _opts) { false } }
        subject = field(if: ->(_name, _object, _opts) { true })

        expect(subject.skip?(:first_name, object, {})).to be_falsey
      end

      # The invalidation caveat: memoized conditions are keyed on Configuration.generation, and the
      # `config.if=`/`config.unless=` writers bump that generation. So global config set *after* a
      # field has already resolved still takes effect on the next call -- the memoization is a hot
      # path optimization, not a snapshot that silently ignores later reconfiguration.
      it 'picks up a global :if configured after first use' do
        subject = field
        expect(subject.skip?(:first_name, object, {})).to be_falsey

        Blueprinter.configure { |config| config.if = ->(_name, _object, _opts) { false } }

        expect(subject.skip?(:first_name, object, {})).to be(true)
      end

      it 'picks up a global :unless configured after first use' do
        subject = field
        expect(subject.skip?(:first_name, object, {})).to be_falsey

        Blueprinter.configure { |config| config.unless = ->(_name, _object, _opts) { true } }

        expect(subject.skip?(:first_name, object, {})).to be(true)
      end

      # Guards the hot path: absent any reconfiguration the generation is unchanged, so the field
      # must not re-resolve (which would re-read global configuration per call, the original bug).
      it 'does not re-resolve while the configuration generation is unchanged' do
        subject = field
        subject.skip?(:first_name, object, {})

        allow(subject).to receive(:callable_from).and_call_original
        5.times { subject.skip?(:first_name, object, {}) }

        expect(subject).not_to have_received(:callable_from)
      end
    end
  end
end

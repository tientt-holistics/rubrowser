require 'json'

module Rubrowser
  module Formatter
    class JSON
      def initialize(data)
        @data = data
      end

      def call
        {
          definitions: data.definitions.map { |d| definition_as_json(d) },
          relations: data.relations.map do |r|
            relation_as_json(r, data.definitions)
          end
        }.to_json
      end

      private

      attr_reader :data

      def definition_as_json(definition)
        {
          type: demoularize(definition.class.name),
          namespace: definition.to_s,
          circular: definition.circular?,
          file: definition.file,
          line: definition.line,
          lines: definition.lines
        }
      end

      def relation_as_json(relation, definitions)
        {
          type: demoularize(relation.class.name),
          namespace: relation.namespace.to_s,
          resolved_namespace: relation.resolve(definitions).to_s,
          caller: relation.caller_namespace.to_s,
          def_name: relation.def_name,
          file: relation.file,
          circular: relation.circular?,
          line: relation.line
        }
      end

      def demoularize(class_name)
        class_name.split('::').last || ''
      end
    end
  end
end

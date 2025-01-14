require 'rubrowser/parser/definition/base'

module Rubrowser
  module Parser
    module Relation
      class Base
        attr_reader :file, :line

        def initialize(namespace, caller_namespace, def_name, target_method, file: nil, line: nil)
          @namespace = namespace
          @caller_namespace = caller_namespace
          @def_name = def_name
          @file = file
          @line = line
          @is_circular = false
          @target_method = target_method
        end

        def namespace
          Definition::Base.new(@namespace, file: file, line: line)
        end

        def caller_namespace
          Definition::Base.new(@caller_namespace, file: file, line: line)
        end

        def def_name
          @def_name
        end

        def target_method
          @target_method
        end

        def circular?
          @is_circular
        end

        def set_circular
          @is_circular = true
        end

        def resolve(definitions)
          possibilities.find do |possibility|
            !definitions.bsearch { |definition| definition <=> possibility }.nil?
          end || possibilities.last
        end

        def ==(other)
          namespace == other.namespace &&
            caller_namespace == other.caller_namespace &&
            circular? == other.circular?
        end

        private

        def possibilities
          if absolute?
            return [
              Definition::Base.new(@namespace.compact, file: file, line: line)
            ]
          end

          possible_parent_namespaces
            .map { |possible_parent| possible_parent + @namespace }
            .push(@namespace)
            .map { |i| Definition::Base.new(i, file: file, line: line) }
        end

        def possible_parent_namespaces
          (@caller_namespace.size - 1)
            .downto(0)
            .map { |i| @caller_namespace[0..i] }
        end

        def absolute?
          @caller_namespace.empty? || @namespace.first.nil?
        end
      end
    end
  end
end

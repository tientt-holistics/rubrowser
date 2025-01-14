require 'parser/current'
require 'rubrowser/parser/definition/class'
require 'rubrowser/parser/definition/module'
require 'rubrowser/parser/relation/base'
require 'rubrowser/parser/file/builder'

module Rubrowser
  module Parser
    class File
      FILE_SIZE_LIMIT = 2 * 1024 * 1024

      attr_reader :file, :definitions, :relations

      def initialize(file)
        @file = ::File.absolute_path(file)
        @definitions = []
        @relations = []
        @variable_type_map = {}
      end

      def parse
        return unless valid_file?(file)

        constants = constants_from_file

        @definitions = constants[:definitions]
        @relations = constants[:relations]
      rescue ::Parser::SyntaxError
        warn "SyntaxError in #{file}"
      end

      def constants_from_file
        contents = ::File.read(file)

        buffer = ::Parser::Source::Buffer.new(file, 1)
        buffer.source = contents.force_encoding(Encoding::UTF_8)

        ast = parser.parse(buffer)

        parse_block(ast)
      end

      def parser
        parser = ::Parser::CurrentRuby.new(Builder.new)
        parser.diagnostics.ignore_warnings = true
        parser.diagnostics.all_errors_are_fatal = false
        parser
      end

      def valid_file?(file)
        !::File.symlink?(file) &&
          ::File.file?(file) &&
          ::File.size(file) <= FILE_SIZE_LIMIT
      end

      private

      def parse_block(node, parents = [], block_name='', target_method='')
        return empty_result unless valid_node?(node)
        case node.type
        when :module then parse_module(node, parents, block_name, target_method)
        when :class then parse_class(node, parents, block_name, target_method)
        when :const then parse_const(node, parents, block_name, target_method)
        when :def then parse_def(node, parents, target_method)
        when :defs then parse_defs(node, parents, target_method)
        when :send then parse_send(node, parents, block_name)
        when :lvasgn then parse_assign(node, parents, block_name, target_method)
        else parse_array(node.children, parents, block_name, target_method)
        end
      end

      def parse_module(node, parents = [], block_name, target_method)
        namespace = ast_consts_to_array(node.children.first, parents)
        definition = build_definition(Definition::Module, namespace, node)
        constants = { definitions: [definition] }
        children_constants = parse_array(node.children[1..-1], namespace, block_name, target_method)

        merge_constants(children_constants, constants)
      end

      def build_definition(klass, namespace, node)
        klass.new(
          namespace,
          file: file,
          line: node.loc.line,
          lines: node.loc.last_line - node.loc.line + 1
        )
      end

      def parse_assign(node, parents = [], block_name, target_method)
        # TODO: handle assign type
        parse_array(node.children, parents, block_name, target_method)
      end

      def parse_send(node, parents, block_name='')
        kaller = node.children[0]
        target = node.children[1]
        params = node.children[2]



        if kaller.nil?
          # self call
          if target.to_s.strip == 'const'
            return parse_array(node.children, parents, "const", "")
          elsif target.to_s.strip == 'raise'
            return parse_array(node.children, parents, "raise", "")
          end
          definition = Relation::Base.new(
            parents,
            parents,
            block_name,
            target,
            file: file,
            line: node.loc.line
          )
          result = { relations: [definition] }
          target_parse_result = parse_block(target, parents, block_name, target)
          params_parse_result = parse_block(params, parents, block_name, target)
          return merge_constants(result, merge_constants(target_parse_result, params_parse_result))
        end

        if kaller.type == :lvar

          variable_name =  node.children[0].to_sexp_array[1]
          variable_type = @variable_type_map.fetch(variable_name, "Untyped")

          definition = Relation::Base.new(
            [variable_type],
            parents,
            block_name,
            node.children[1],
            file: file,
            line: node.loc.line
          )
          result = { relations: [definition] }
          target_parse_result = parse_block(target, parents, block_name, target)
          params_parse_result = parse_block(params, parents, block_name, target)
          return merge_constants(result, merge_constants(target_parse_result, params_parse_result))
        end

        if kaller.type == :send
          definition = Relation::Base.new(
            ["Untyped"],
            parents,
            block_name,
            node.children[1],
            file: file,
            line: node.loc.line
          )
          result = { relations: [definition] }
          target_parse_result = parse_block(target, parents, block_name, target)
          params_parse_result = parse_block(params, parents, block_name, target)
          return merge_constants(result, merge_constants(target_parse_result, params_parse_result))
        end

        parse_array(node.children, parents, block_name, target)
      end

      def parse_defs(node, parents, target_method)
        parse_array(node.children, parents, node.to_sexp_array[2])
      end

      def parse_def(node, parents, target_method)
        parse_array(node.children, parents, node.to_sexp_array[1])
      end

      def parse_class(node, parents = [], block_name='', target_method)
        namespace = ast_consts_to_array(node.children.first, parents)
        definition = build_definition(Definition::Class, namespace, node)
        constants = { definitions: [definition] }
        children_constants = parse_array(node.children[1..-1], namespace, block_name, target_method)

        merge_constants(children_constants, constants)
      end

      def parse_const(node, parents = [], block_name='', target_method = '')
        constant = ast_consts_to_array(node)
        definition = Relation::Base.new(
          constant,
          parents,
          block_name,
          target_method,
          file: file,
          line: node.loc.line
        )
        { relations: [definition] }
      end

      def parse_array(arr, parents = [], block_name='', target_method='')
        arr.map { |n| parse_block(n, parents, block_name, target_method) }
           .reduce { |a, e| merge_constants(a, e) }
      end

      def merge_constants(const1, const2)
        const1 ||= {}
        const2 ||= {}
        {
          definitions: const1[:definitions].to_a + const2[:definitions].to_a,
          relations: const1[:relations].to_a + const2[:relations].to_a
        }
      end

      def ast_consts_to_array(node, parents = [])
        return parents unless valid_node?(node) &&
                              %I[const cbase].include?(node.type)

        ast_consts_to_array(node.children.first, parents) + [node.children.last]
      end

      def empty_result
        {}
      end

      def valid_node?(node)
        node.is_a?(::Parser::AST::Node)
      end
    end
  end
end

require 'bel_parser/language/expression_validator'
require 'bel_parser/language/semantics'
require 'bel_parser/resource'
require 'bel_parser/parsers/ast/node'
require 'bel_parser/parsers/expression/statement_autocomplete'
require 'bel_parser/parsers/serializer'
require_relative 'mixin/levenshtein'

module BELParser
  module Completion
    extend BELParser::Parsers::AST::Sexp
    extend BELParser::Parsers

    def self.complete(input, spec, search, namespaces,
                      caret_position = input.length, include_invalid_semantics = false)
      # Algorithm
      # 1. Parse AST using statement_autocomplete ragel FSM.
      # 2. Given cursor find node to complete.
      # 3. Determine completers that should run given node type and surrounding nodes in the AST.
      # 4. Compute completion AST for each suggestion.
      # 5. For each suggestion, transform original AST into full completion.
      # 6. Run semantic validation on each completion AST.
      # 7. Return combined completion AST and semantic details.

      ast, caret_position = BELParser::Parsers::Expression::StatementAutocomplete.parse(input, caret_position)
      completing_node     = find_node(ast, caret_position)
      return [] unless completing_node

      completions =
        case completing_node.type
        when :parameter
          complete_parameter(completing_node, caret_position, ast, spec, search, namespaces)
        when :function
          complete_function(completing_node, caret_position, ast, spec, search, namespaces)
        when :argument
          complete_argument(completing_node, caret_position, ast, spec, search, namespaces)
        when :relationship
          complete_relationship(completing_node, caret_position, ast, spec, search, namespaces)
        else
          []
        end

      will_match_partial = true
      urir               = BELParser::Resource.default_uri_reader
      urlr               = BELParser::Resource.default_url_reader

      validator =
        BELParser::Language::ExpressionValidator.new(
          spec, namespaces, urir, urlr, will_match_partial
        )

      validated_completions =
        completions
          .map { |(completion_ast, completion_result)|

            if completion_result[:type] == :namespace_prefix
              # namespace_prefix completions are always valid
              completion_result[:validation] = {
                expression:      completion_result[:value],
                valid_syntax:    true,
                valid_semantics: true,
                message:         'Valid semantics',
                warnings:        [],
                term_signatures: []
              }
              completion_result
            else
              message             = ''
              terms               = completion_ast.traverse.select { |node| node.type == :term }.to_a
              semantics_functions =
                BELParser::Language::Semantics.semantics_functions.reject { |fun|
                  fun == BELParser::Language::Semantics::SignatureMapping
                }

              semantic_warnings =
                completion_ast
                  .traverse
                  .flat_map { |node|
                    semantics_functions.flat_map { |func|
                      func.map(node, spec, namespaces, will_match_partial)
                    }
                  }
                  .compact

              if semantic_warnings.empty?
                valid = true
              else
                valid = false
                message =
                  semantic_warnings.reduce('') { |msg, warning|
                    msg << "#{warning}\n"
                  }
                message << "\n"
              end

              term_semantics =
                terms.map { |term|
                  term_result = validator.validate(term)
                  valid      &= term_result.valid_semantics?
                  bel_term    = serialize(term)

                  unless valid
                    message << "Term: #{bel_term}\n"
                    term_result.invalid_signature_mappings.map { |m|
                      message << "  #{m}\n"
                    }
                    message << "\n"
                  end

                  {
                    term:               bel_term,
                    valid_signatures:   term_result.valid_signature_mappings.map(&:to_s),
                    invalid_signatures: term_result.invalid_signature_mappings.map(&:to_s)
                  }
                }

              completion_result[:validation] = {
                expression:      completion_result[:value],
                valid_syntax:    true,
                valid_semantics: valid,
                message:         valid ? 'Valid semantics' : message,
                warnings:        semantic_warnings.map(&:to_s),
                term_signatures: term_semantics
              }
              completion_result
            end
          }
          .group_by { |completion_result|
            completion_result[:validation][:valid_semantics]
          }

      if include_invalid_semantics
        (validated_completions[true] || []) + (validated_completions[false] || [])
      else
        validated_completions[true] || []
      end
    end

    def self.complete_function(
      completing_node, caret_position, ast, spec, search, namespaces
    )
      string_literal =
        if completing_node.identifier.nil?
          ''
        else
          completing_node.identifier.string_literal
        end

      FunctionCompleter
        .new(spec, search, namespaces)
        .complete(string_literal, caret_position)
        .map { |(function, completion_ast)|
          short      = function.short.to_s
          long       = function.long.to_s

          completion_ast.character_range = [
            completing_node.range_start,
            completing_node.range_start + short.length
          ]

          completion_ast = MergeCompletion.new(completion_ast).process(ast)
          completion     = serialize(completion_ast)

          [
            completion_ast,
            {
              type:           :function,
              id:             long,
              label:          long,
              value:          completion,
              caret_position: short.length + 1
            }
          ]
        }
    end

    def self.complete_relationship(
      completing_node, caret_position, ast, spec, search, namespaces
    )
      string_literal = completing_node.string_literal

      completer =
        if string_literal.nil?
          AllRelationshipCompleter.new(spec, search, namespaces)
        else
          RelationshipCompleter.new(spec, search, namespaces)
        end

      completer
        .complete(string_literal, caret_position)
        .map { |(relationship, completion_ast)|
          short = relationship.short.to_s
          long  = relationship.long.to_s

          completion_ast.character_range = [
            completing_node.range_start,
            completing_node.range_start + short.length
          ]

          completion_ast = MergeCompletion.new(completion_ast).process(ast)
          completion     = serialize(completion_ast)

          [
            completion_ast,
            {
              type:           :relationship,
              id:             long,
              label:          long,
              value:          completion,
              caret_position: short.length + 1
            }
          ]
        }
    end

    def self.complete_parameter(
      completing_node, caret_position, ast, spec, search, namespaces
    )
      prefix, value = completing_node.children

      # Completing prefix
      if Range.new(*prefix.character_range, false).include?(caret_position)
        if prefix.identifier.nil?
          # Provide all namespace prefix completions.
          all_prefix_completions = AllNamespacePrefixCompleter
            .new(spec, search, namespaces)
            .complete(nil, nil)
            .map { |(bel_prefix, completion_ast)|
              completion_ast.character_range = [
                prefix.range_start,
                prefix.range_start + bel_prefix.length + 1
              ]

              completion_ast = MergeCompletion.new(completion_ast).process(ast)
              completion     = serialize(completion_ast)

              [
                completion_ast,
                {
                  type:           :namespace_prefix,
                  id:             bel_prefix,
                  label:          bel_prefix,
                  value:          completion,
                  caret_position: completing_node.range_start + bel_prefix.length + 1
                }
              ]
            }

          all_prefix_completions
        else
          # Match provided namespace prefix.
          string_literal = prefix.identifier.string_literal

          prefix_completions = NamespacePrefixCompleter
            .new(spec, search, namespaces)
            .complete(string_literal, caret_position)
            .map { |(bel_prefix, completion_ast)|
              completion_ast.character_range = [
                prefix.range_start,
                prefix.range_start + bel_prefix.length + 1
              ]

              completion_ast = MergeCompletion.new(completion_ast).process(ast)
              completion     = serialize(completion_ast)

              [
                completion_ast,
                {
                  type:           :namespace_prefix,
                  id:             bel_prefix,
                  label:          bel_prefix,
                  value:          completion,
                  caret_position: completing_node.range_start + bel_prefix.length + 1
                }
              ]
            }

          prefix_completions
        end
      else
        string_literal =
          case value.first_child.type
          when :identifier
            value.first_child.string_literal
          when :string
            value.first_child.string_value
          end

        prefix_str =
          if prefix && prefix.identifier
            prefix.identifier.string_literal
          else
            nil
          end

        function_completions = FunctionTermCompleter
          .new(spec, search, namespaces)
          .complete(string_literal, caret_position)
          .map { |(function, completion_ast)|
            short      = function.short.to_s
            long       = function.long.to_s
            completion = serialize(completion_ast)

            [
              completion_ast,
              {
                type:           :function,
                id:             long,
                label:          long,
                value:          completion,
                caret_position: short.length + 1
              }
            ]
          }

        prefix_completions = NamespacePrefixArgumentCompleter
          .new(spec, search, namespaces)
          .complete(string_literal, nil)
          .map { |(bel_prefix, completion_ast)|
            completion = serialize(completion_ast)

            [
              completion_ast,
              {
                type:           :namespace_prefix,
                id:             bel_prefix,
                label:          bel_prefix,
                value:          completion,
                caret_position: completing_node.range_start + bel_prefix.length + 1
              }
            ]
          }

        exact_match_completions = ExactMatchParameterCompleter
          .new(spec, search, namespaces)
          .complete(string_literal, caret_position - value.range_start, prefix: prefix_str)
          .map { |(ns_value, completion_ast)|
            completion = "(#{serialize(completion_ast)})"

            [
              completion_ast,
              {
                type:           :namespace_value,
                id:             ns_value,
                label:          ns_value,
                value:          completion,
                caret_position: 0
              }
            ]
          }

        wildcard_completions = WildcardMatchParameterCompleter
          .new(spec, search, namespaces)
          .complete(string_literal, caret_position - value.range_start, prefix: prefix_str)
          .map { |(ns_value, completion_ast)|
            completion = "(#{serialize(completion_ast)})"

            [
              completion_ast,
              {
                type:           :namespace_value,
                id:             ns_value,
                label:          ns_value,
                value:          completion,
                caret_position: 0
              }
            ]
          }

        function_completions + prefix_completions + (exact_match_completions + wildcard_completions).uniq
      end
    end

    def self.complete_argument(
      completing_node, caret_position, ast, spec, search, namespaces
    )
      if completing_node.child.nil?
        all_prefix_completions = AllNamespacePrefixArgumentCompleter
          .new(spec, search, namespaces)
          .complete(nil, nil)
          .map { |(bel_prefix, completion_ast)|
            completion_ast.character_range = completing_node.character_range

            completion_ast = MergeCompletion.new(completion_ast).process(ast)
            completion     = serialize(completion_ast)

            [
              completion_ast,
              {
                type:           :namespace_prefix,
                id:             bel_prefix,
                label:          bel_prefix,
                value:          completion,
                caret_position: completing_node.range_start + bel_prefix.length + 1
              }
            ]
          }

        all_function_completions = AllFunctionArgumentCompleter
          .new(spec, search, namespaces)
          .complete(nil, nil)
          .map { |(function, completion_ast)|
            short = function.short.to_s
            long  = function.long.to_s

            completion_ast.character_range = [
              completing_node.range_start,
              completing_node.range_start + short.length
            ]

            completion_ast = MergeCompletion.new(completion_ast).process(ast)
            completion     = serialize(completion_ast)

            [
              completion_ast,
              {
                type:           :function,
                id:             long,
                label:          long,
                value:          completion,
                caret_position: short.length + 1
              }
            ]
          }

        all_prefix_completions + all_function_completions
      elsif completing_node.parameter?
        parameter     = completing_node.child
        prefix, value = parameter.children

        if prefix && Range.new(*prefix.character_range, false).include?(caret_position)
          prefix_str = prefix.identifier.string_literal

          prefix_completions = NamespacePrefixArgumentCompleter
            .new(spec, search, namespaces)
            .complete(prefix_str, nil)
            .map { |(bel_prefix, completion_ast)|
              completion_ast.character_range = completing_node.character_range

              completion_ast = MergeCompletion.new(completion_ast).process(ast)
              completion     = serialize(completion_ast)

              [
                completion_ast,
                {
                  type:           :namespace_prefix,
                  id:             bel_prefix,
                  label:          bel_prefix,
                  value:          completion,
                  caret_position: completing_node.range_start + bel_prefix.length + 1
                }
              ]
            }

          prefix_completions
        else
          # completing value of parameter
          value_str =
            case value.first_child.type
            when :identifier
              value.first_child.string_literal
            when :string
              value.first_child.string_value
            end

          prefix_string      = nil
          prefix_completions =
            if prefix && prefix.identifier
              # ... prefix exists, store it for later value lookup
              prefix_string = prefix.identifier.string_literal
              []
            else
              # ... prefix is nil, try to complete it, lookup values later without prefix
              prefix_string = nil

              NamespacePrefixArgumentCompleter
                .new(spec, search, namespaces)
                .complete(value_str, nil)
                .map { |(bel_prefix, completion_ast)|
                  completion_ast.character_range = completing_node.character_range

                  completion_ast = MergeCompletion.new(completion_ast).process(ast)
                  completion     = serialize(completion_ast)

                  [
                    completion_ast,
                    {
                      type:           :namespace_prefix,
                      id:             bel_prefix,
                      label:          bel_prefix,
                      value:          completion,
                      caret_position: completion_ast.range_start + bel_prefix.length + 1
                    }
                  ]
                }
            end

          function_completions = []
          if prefix_string.nil?
            completer =
              if ast.subject.term.function.nil? || (!ast.object.nil? && ast.object.term? && ast.object.child.function.nil?)
                FunctionTermCompleter
              else
                FunctionArgumentCompleter
              end
            function_completions = completer
              .new(spec, search, namespaces)
              .complete(value_str, caret_position)
              .map { |(function, completion_ast)|
                short = function.short.to_s
                long  = function.long.to_s

                completion_ast.character_range = [
                  completing_node.range_start,
                  completing_node.range_start + short.length
                ]

                completion_ast = MergeCompletion.new(completion_ast).process(ast)
                completion     = serialize(completion_ast)

                [
                  completion_ast,
                  {
                    type:           :function,
                    id:             long,
                    label:          long,
                    value:          completion,
                    caret_position: completing_node.range_start + short.length + 1
                  }
                ]
              }
          end

          exact_match_completions = ExactMatchParameterCompleter
            .new(spec, search, namespaces)
            .complete(value_str, caret_position - value.range_start, prefix: prefix_string)
            .map { |(ns_value, completion_ast)|
              completion_ast.character_range = completing_node.character_range

              completion_ast = MergeCompletion.new(completion_ast).process(ast)
              completion     = serialize(completion_ast)

              [
                completion_ast,
                {
                  type:           :namespace_value,
                  id:             ns_value,
                  label:          ns_value,
                  value:          completion,
                  caret_position: value.range_start + ns_value.length
                }
              ]
            }

          wildcard_completions = WildcardMatchParameterCompleter
            .new(spec, search, namespaces)
            .complete(value_str, caret_position - value.range_start, prefix: prefix_string)
            .map { |(ns_value, completion_ast)|
              completion_ast.character_range = completing_node.character_range

              completion_ast = MergeCompletion.new(completion_ast).process(ast)
              completion     = serialize(completion_ast)

              [
                completion_ast,
                {
                  type:           :namespace_value,
                  id:             ns_value,
                  label:          ns_value,
                  value:          completion,
                  caret_position: value.range_start + ns_value.length
                }
              ]
            }

          prefix_completions + function_completions + (exact_match_completions + wildcard_completions).uniq
        end
      else
        # TODO Completing term argument, will we ever get here?
        puts "#{completing_node.type}: child is a term, how do we proceed?"
        []
      end
    end

    def self.find_node(ast, caret_position)
      ast.traverse do |node|
        next if
          node.type == :term ||
          caret_position < node.range_start ||
          caret_position > node.range_end

        case node.type
        when :argument
          return node if node.child.nil? || node.parameter?
        when :parameter, :function, :relationship
          return node
        end
      end

      nil
    end

    class BaseCompleter
      include BELParser::Parsers::AST::Sexp

      def initialize(spec, search, namespaces)
        @spec       = spec
        @search     = search
        @namespaces = namespaces
      end

      def complete(string_literal, caret_position, options = {})
        raise NotImplementedError, "#{__method__} is not implemented."
      end
    end

    class FunctionCompleter < BaseCompleter

      def complete(string_literal, caret_position)
        pattern = /.*#{Regexp.quote(string_literal)}.*/i
        @spec.functions
          .select  { |function| function =~ pattern }
          .sort_by { |function| function.long       }
          .map     { |function|
            make_completion(function)
          }
      end

      protected

      def make_completion(function)
        [
          function,
          function(
            identifier(
              function.short.to_s))
        ]
      end
    end

    class FunctionTermCompleter < FunctionCompleter

      def make_completion(function)
        [
          function,
          term(
            function(
              identifier(
                function.short.to_s)))
        ]
      end
    end

    class FunctionArgumentCompleter < FunctionCompleter

      def make_completion(function)
        [
          function,
          argument(
            term(
              function(
                identifier(
                  function.short.to_s))))
        ]
      end
    end

    class AllFunctionCompleter < BaseCompleter

      def complete(_, _)
        @spec.functions
          .sort_by { |function| function.long }
          .map     { |function|
            make_completion(function)
          }
      end

      protected

      def make_completion(function)
        [
          function,
          function(
            identifier(
              function.short.to_s))
        ]
      end
    end

    class AllFunctionTermCompleter < AllFunctionCompleter

      def make_completion(function)
        [
          function,
          term(
            function(
              identifier(
                function.short.to_s)))
        ]
      end
    end

    class AllFunctionArgumentCompleter < AllFunctionCompleter

      def make_completion(function)
        [
          function,
          argument(
            term(
              function(
                identifier(
                  function.short.to_s))))
        ]
      end
    end

    class NamespacePrefixCompleter < BaseCompleter

      def complete(string_literal, _)
        lowercase_substring = string_literal.upcase
        @namespaces.keys
          .select  { |px| px.include?(lowercase_substring) }
          .sort
          .map     { |px|
            make_completion(px.upcase)
          }
      end

      protected

      def make_completion(bel_prefix)
        [
          bel_prefix,
          prefix(
            identifier(
              bel_prefix))
        ]
      end
    end

    class NamespacePrefixArgumentCompleter < NamespacePrefixCompleter

      def make_completion(prefix)
        [
          prefix,
          argument(
            parameter(
              prefix(
                identifier(
                  prefix)),
              value(
                identifier(
                  ""))))
        ]
      end
    end

    class AllNamespacePrefixCompleter < NamespacePrefixCompleter

      def complete(_, _)
        @namespaces.keys
          .sort
          .map { |px|
            make_completion(px)
          }
      end
    end

    class AllNamespacePrefixArgumentCompleter < NamespacePrefixArgumentCompleter

      def complete(_, _)
        @namespaces.keys
          .sort
          .map { |px|
            make_completion(px)
          }
      end
    end

    module QuotedValue

      def map_value(prefix, pref_label)
        if !pref_label.scan(/[^\w]/).empty?
          [
            %Q{#{prefix}:"#{pref_label}"},
            value(
              string(
                pref_label))
          ]
        else
          [
            %Q{#{prefix}:#{pref_label}},
            value(
              identifier(
                pref_label))
          ]
        end
      end
    end

    class WildcardMatchParameterCompleter < BaseCompleter
      include QuotedValue

      L = BELParser::Levenshtein

      def complete(string_literal, caret_position, options = {})
        return [] if string_literal.length < 3

        query =
          case
          when caret_position == string_literal.length
            "#{string_literal}*"
          when caret_position == 0
            "*#{string_literal}"
          else
            ante = string_literal.slice(0...caret_position)
            post = string_literal.slice(caret_position..-1)
            "#{ante}*#{post}"
          end

        # find namespace URI if prefix was provided
        prefix = options[:prefix]
        if prefix
          specified_prefix  = prefix.to_s.upcase
          matched_namespace = @namespaces[specified_prefix]
          uri               = matched_namespace ? matched_namespace.uri : nil
        else
          uri = nil
        end

        @search
          .search(query, :namespace_concept, uri, nil, size: 100)
          .sort { |match1, match2|
            L.distance(string_literal.downcase, match1.pref_label.downcase) <=>
            L.distance(string_literal.downcase, match2.pref_label.downcase)
          }
          .map { |match|
            match_namespace = @namespaces.values.find { |ns| ns.uri == match.scheme_uri }
            if match_namespace
              [match_namespace.keyword, match.pref_label]
            else
              nil
            end
          }
          .compact
          .take(20)
          .sort_by { |(_, v)| v }
          .uniq
          .map     { |(ns, v)|
            ns_value, value_ast = map_value(ns, v)

            [
              ns_value,
              argument(
                parameter(
                  prefix(
                    identifier(
                      ns)),
                  value_ast))
            ]
          }
      end
    end

    class ExactMatchParameterCompleter < BaseCompleter
      include QuotedValue

      def complete(string_literal, caret_position, options = {})
        # find namespace URI if prefix was provided
        prefix = options[:prefix]
        if prefix
          specified_prefix  = prefix.to_s.upcase
          matched_namespace = @namespaces[specified_prefix]
          uri               = matched_namespace ? matched_namespace.uri : nil
        else
          uri = nil
        end

        @search
          .search(string_literal, :namespace_concept, uri, nil, size: 100, exact_match: true)
          .map { |match|
            match_namespace = @namespaces.values.find { |ns| ns.uri == match.scheme_uri }
            next unless match_namespace

            prefix              = match_namespace.keyword
            ns_value, value_ast = map_value(prefix, match.pref_label)

            [
              ns_value,
              argument(
                parameter(
                  prefix(
                    identifier(
                      prefix)),
                  value_ast))
            ]
          }
          .to_a
          .compact
      end
    end

    class RelationshipCompleter < BaseCompleter

      def complete(string_literal, caret_position)
        @spec.relationships
          .select  { |relationship|
            relationship =~ /.*#{Regexp.quote(string_literal)}.*/i
          }
          .sort_by { |relationship| relationship.long }
          .map     { |relationship|
            make_completion(relationship)
          }
      end

      def make_completion(relationship)
        short = relationship.short.to_s
        [
          relationship,
          relationship(
            short)
        ]
      end
    end

    class AllRelationshipCompleter < RelationshipCompleter

      def complete(string_literal, caret_position)
        @spec.relationships
          .sort_by { |relationship| relationship.long }
          .map     { |relationship|
            make_completion(relationship)
          }
      end
    end

    class MergeCompletion
      include ::AST::Processor::Mixin

      def initialize(completion_node)
        @completion_node = completion_node
        @target_type     = completion_node.type
        @range_start     = completion_node.range_start
      end

      def handler_missing(node)
        if node.type == @target_type && node.range_start == @range_start
          node = @completion_node
        end

        node.updated(
          node.children.map { |n|
            if n.respond_to?(:type)
              process(n)
            else
              n
            end
          }
        )
      end
    end
  end
end

if RUBY_ENGINE =~ /jruby/ && __FILE__ == $0
  require 'bel_parser'
  require 'bel_parser/resource/jena_tdb_reader'
  require 'bel'

  # RdfRepository using Jena.
  tdb        = ARGV.shift
  rr         = BEL::RdfRepository.plugins[:jena].create_repository(:tdb_directory => tdb)
  namespaces = BEL::Resource::Namespaces.new(rr)

  BELParser::Resource.default_uri_reader = BELParser::Resource::JenaTDBReader.new(tdb)

  ns_hash = Hash[
    namespaces.each.map { |ns|
      prefix = ns.prefix.first.upcase

      [
        prefix,
        BELParser::Expression::Model::Namespace.new(
          prefix,
          ns.uri
        )
      ]
    }
  ]


  puts "Available namespaces:"
  ns_hash.each do |_, ns|
    puts "  #{ns.keyword}: #{ns.uri}"
  end

  spec   = BELParser::Language.specification('2.0')
  search = BEL::Resource::Search.plugins[:sqlite].create_search(
    :database_file => '/home/tony/projects/openbel/openbel-api/data/rdf_resources.db'
  )

  $stdin.each_line do |line|
    line.strip!
    puts BELParser::Completion.complete(line, spec, search, ns_hash)
  end
end
# vim: ft=ruby ts=2 sw=2:
# encoding: utf-8

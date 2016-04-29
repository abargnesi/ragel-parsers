require_relative 'parsers/common'
require_relative 'parsers/expression'
require_relative 'parsers/bel_script'
require_relative 'mixin/line_mapping'
require_relative 'mixin/line_continuator'

module BELParser
  # ASTGenerator yields AST results for each line in some {IO}.
  # See #{ASTGenerator#each}.
  class ASTGenerator
    include LineMapping
    include LineContinuator

    map_const = ->(x) { x.constants.map { |c| x.const_get(c) } }
    PARSERS = [
      map_const.call(BELParser::Parsers::Common),
      map_const.call(BELParser::Parsers::Expression),
      map_const.call(BELParser::Parsers::BELScript)
    ].flatten!

    def initialize(io)
      @io = io
    end

    # Yields AST results for each line of the IO.
    #
    # @example Receive AST results in given block.
    #   # doctest setup require 'bel_parser' self.class.include AST::Sexp
    #
    #   # example usage line_io = StringIO.new("\"AKT1\"\n") line    =
    #   nil ast_res = nil ::BELParser::ASTGenerator.new.each(line_io)
    #   { |(line_number, line, results)|
    #     # do something
    #   }
    #
    # @example Receive AST results as an enumerator.
    #   # doctest setup require 'bel_parser' self.class.include AST::Sexp
    #
    #   # example usage line_io = StringIO.new("\"AKT1\"\n") line,
    #   ast_res = ::BELParser::ASTGenerator.new.each(line_io).first.to_a
    #
    # @param  [IO] io the IO-object to read each line from @yield
    # [[Integer, String, Array<AST::Node>]] yields line number, line,
    #         and AST results as an {Array}
    # @return [IO, #<Enumerator: #<BELParser::ASTGenerator#each>] the {IO}
    #         object is returned if a block is given, otherwise an
    #         {Enumerator} object is returned that can be iterated with
    #         {Enumerator#each}
    def each # rubocop:disable MethodLength
      if block_given?
        line_enumerator = map_lines(@io.each_line.lazy)

        line_number = 1
        loop do
          begin
            line = expand_line_continuator(line_enumerator)

            ast_results = []
            PARSERS.map do |parser|
              parser.parse(line) { |ast| ast_results << ast }
            end
            yield [line_number, line, ast_results]
            line_number += 1
          rescue StopIteration
            return
          end
        end
      else
        enum_for(:each)
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  BELParser::ASTGenerator.new.each($stdin) do |line_results|
    line_number, line, ast_results = line_results
    puts "#{line_number}: #{line}"
    ast_results.each do |ast|
      puts ast.to_s(1)
    end
  end
end

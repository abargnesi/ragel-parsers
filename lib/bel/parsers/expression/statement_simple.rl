# begin: ragel
=begin
%%{
  machine bel;

  include 'term.rl';
  include 'relationship.rl';
  include 'comment.rl';

  action statement_subject {
    @buffers[:subject]    = subject(
                              @buffers[:term_stack][-1])
    @buffers[:term_stack] = nil
  }

  action statement_object {
    @buffers[:object]     = object(
                              @buffers[:term_stack][-1])
    @buffers[:term_stack] = nil
  }

  action yield_statement_simple {
    @buffers[:comment] ||= comment(nil)
    yield statement_simple(
            statement(
              @buffers[:subject],
              @buffers[:relationship],
              @buffers[:object],
              @buffers[:comment]))
  }

  STATEMENT_SIMPLE =
    outer_term %statement_subject
    SP+
    RELATIONSHIP
    SP+
    outer_term %statement_object;

  statement_simple :=
    STATEMENT_SIMPLE
    SP*
    COMMENT? %yield_statement_simple
    NL;
}%%
=end
# end: ragel

require_relative '../ast/node'
require_relative '../mixin/buffer'
require_relative '../nonblocking_io_wrapper'

module BEL
  module Parsers
    module Expression
      module StatementSimple

        class << self

          MAX_LENGTH = 1024 * 128 # 128K

          def parse(content)
            return nil unless content

            Parser.new(content).each do |obj|
              yield obj
            end
          end
        end

        private

        class Parser
          include Enumerable
          include BEL::Parsers::Buffer
          include BEL::Parsers::AST::Sexp

          def initialize(content)
            @content = content
      # begin: ragel        
            %% write data;
      # end: ragel        
          end

          def each
            @buffers = {}
            stack    = []
            data     = @content.unpack('C*')
            p        = 0
            pe       = data.length
            eof      = data.length

      # begin: ragel        
            %% write init;
            %% write exec;
      # end: ragel        
          end
        end
      end
    end
  end
end

if __FILE__ == $0
  $stdin.each_line do |line|
    BEL::Parsers::Expression::StatementSimple.parse(line) { |obj|
      puts obj.inspect
    }
  end
end

# vim: ft=ruby ts=2 sw=2:
# encoding: utf-8

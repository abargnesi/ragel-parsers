# begin: ragel
=begin
%%{
  machine bel;

  include 'term.rl';
  include 'comment.rl';

  action yield_statement_observed_term {
    @buffers[:comment] ||= comment(nil)
    yield observed_term(
            statement(
              subject(@buffers[:term_stack][-1]),
              relationship(nil),
              object(nil),
              @buffers[:comment]))
  }

  statement_observed_term :=
    outer_term 
    SP*
    COMMENT? %yield_statement_observed_term
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
      module StatementObservedTerm

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
    BEL::Parsers::Expression::StatementObservedTerm.parse(line) { |obj|
      puts obj.inspect
    }
  end
end

# vim: ft=ruby ts=2 sw=2:
# encoding: utf-8

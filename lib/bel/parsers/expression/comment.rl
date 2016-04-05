# begin: ragel
=begin
%%{
  machine bel;

  include 'common.rl';

  action start_comment {
    @buffers[:comment] = []
  }

  action append_comment {
    @buffers[:comment] << fc
  }

  action finish_comment {
    @buffers[:comment] = comment(
                           utf8_string(@buffers[:comment]))
  }

  action yield_comment {
    yield @buffers[:comment] || comment(nil)
  }

  COMMENT = '//' ^NL+ >start_comment $append_comment %finish_comment;

  comment :=
    COMMENT? %yield_comment
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
      module Comment

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
    BEL::Parsers::Expression::Comment.parse(line) { |obj|
      puts obj.inspect
    }
  end
end

# vim: ft=ruby ts=2 sw=2:
# encoding: utf-8

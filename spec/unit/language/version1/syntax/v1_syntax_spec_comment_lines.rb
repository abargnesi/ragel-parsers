require_relative '../../../spec_helper'
require 'bel_parser/parsers/ast/node'
require 'bel_parser/parsers/common'
require 'bel_parser/parsers/expression'
require 'bel_parser/parsers/bel_script'

ast = BELParser::Parsers::AST
parsers = BELParser::Parsers

describe 'when parsing comment lines' do
  subject(:parser) { parsers::Common::CommentLine }

  include ::AST::Sexp

  it 'is incomplete for \'\'' do
    output = parse_ast(parser, '')
    expect(output).to be_a(ast::CommentLine)
    expect(output).to respond_to(:complete)
    expect(output.complete).to be(false)
    expect(output.children?).to be(true)
    expect(output).to eq(
      s(:comment_line, '')
    )
  end

  it 'is complete for single character input #' do
    output = parse_ast(parser, '#')
    expect(output).to be_a(ast::CommentLine)
    expect(output).to respond_to(:complete)
    expect(output.complete).to be(true)
    expect(output.children?).to be(true)
    expect(output).to eq(
      s(:comment_line, '')
    )
  end

  it 'is complete with leading spaces' do
    output = parse_ast(parser, '  #')
    expect(output).to be_a(ast::CommentLine)
    expect(output).to respond_to(:complete)
    expect(output.complete).to be(true)
    expect(output.children?).to be(true)
    expect(output).to eq(
      s(:comment_line, '')
    )
  end

  it 'is complete with typical input' do
    output = parse_ast(parser, '# Blah blah.')
    expect(output).to be_a(ast::CommentLine)
    expect(output).to respond_to(:complete)
    expect(output.complete).to be(true)
    expect(output.children?).to be(true)
    expect(output).to eq(
      s(:comment_line, 'Blah blah.')
    )
  end
end

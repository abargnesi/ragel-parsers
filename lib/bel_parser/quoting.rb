module BELParser
  # The Quoting module implements quoting rules consistent with BEL
  # and BEL Script. Double quotes are used to group a string together
  # which may contain whitespace or special characters.
  #
  # A value can either be an identifier or a string value. An
  # identifier can only include the characters +[0-9A-Za-z_]+. A string
  # value is necessary when at least one of +[^0-9A-Za-z_]+ exists in
  # the value.
  #
  # Uses:
  #
  # BEL: The BEL parameters must be an identifier or string value.
  #
  # BEL Script: BEL parameters, document property values, and annotation
  # values must be an identifier or string value.
  module Quoting
    # Declares BEL Script keywords that cause problems with the OpenBEL
    # Framework parser.
    Keywords               = %w(SET DEFINE a g p r m).freeze

    # Regular expression that matches one of {Quoting::Keywords}.
    KeywordMatcher         = Regexp.compile(/^(#{Keywords.join('|')})$/)

    # Regular expression that matches on any non-word character.
    NonWordMatcher         = Regexp.compile(/[^0-9a-zA-Z_]/)

    # Regular expression that matches a value surrounded by unescaped
    # double quotes.
    StrictQuotedMatcher    = Regexp.compile(/\A".*?(?<!\\)"\Z/m)

    # Regular expression that matches a value surrounded by double quotes
    # that may be escaped.
    LenientQuotedMatcher   = Regexp.compile(/\A".*?"\Z/m)

    # Regular expression that matches double quotes that are not escaped.
    QuoteNotEscapedMatcher = Regexp.compile(/(?<!\\)"/m)

    # Returns +value+ surrounded by double quotes. This method is idempotent
    # so +value+ will only be quoted once regardless of how may times the
    # method is called on it.
    #
    # @example Quoting a BEL parameter.
    #    quote("apoptotic process")
    #    # => "\"apoptotic process\""
    # @example Escaping quotes within a value.
    #    quote("vesicle fusion with \"Golgi apparatus\"")
    #    # => "\"vesicle fusion with \\\"Golgi apparatus\\\"\""
    #
    # @parameter [#to_s] value a value to be quoted
    # @return    [String] value surrounded by double quotes
    def quote(value)
      string   = value.to_s
      unquoted = unquote(string)
      escaped  = unquoted.gsub(QuoteNotEscapedMatcher, '\\"')
      %("#{escaped}")
    end

    # Returns +value+ with surrounded quotes removed.
    #
    # @example Unquoting a BEL parameter.
    #    unquote("\"apoptotic process\"")
    #    # => "apoptotic process"
    # @example Escaped quotes are preserved.
    #    unquote("\"vesicle fusion with \"Golgi apparatus\"\"")
    #
    # @parameter [#to_s]  value a value to be unquoted
    # @return    [String] value with surrounding double quotes removed
    def unquote(value)
      string = value.to_s
      if string =~ StrictQuotedMatcher
        string[1...-1]
      else
        string
      end
    end

    # Returns +value+ with quoting applied only if necessary. A +value+
    # consisting of only word character (e.g. [0-9A-Za-z_]) does not need
    # quoting. A +value+ consisting of at least one non-word character
    # (e.g. [^0-9A-Za-z_]) will requiring quoting.
    #
    # @example Quotes added when value includes spaces.
    #    quote_if_needed("apoptotic process")
    #    # => "\"apoptotic process\""
    # @example Quotes added when value includes double quote.
    #    quote_if_needed("vesicle fusion with \"Golgi apparatus\"")
    #    # => "\"vesicle fusion with \\\"Golgi apparatus\\\"\""
    # @example No quotes necessary for identifier.
    #    quote_if_needed("AKT1_HUMAN")
    #    # => "AKT1_HUMAN"
    #
    # @parameter [#to_s]  value that may be quoted
    # @return    [String] original value or quoted value
    def quote_if_needed(value)
      if string_value?(value)
        quote(value)
      else
        value.to_s
      end
    end

    # Returns whether the +value+ is surrounded by double quotes.
    #
    # @example Returns +true+ when value is quoted.
    #    quoted?("\"vesicle fusion with \"Golgi apparatus\"")
    #    # => true
    # @example Returns +false+ when value is not quoted.
    #    quoted?("apoptotic process")
    #    # => false
    #
    # @parameter [#to_s]   value to test
    # @return    [Boolean] +true+ if +value+ is quoted, +false+ if
    #            +value+ is not quoted
    def quoted?(value)
      string = value.to_s
      (string =~ LenientQuotedMatcher) != nil
    end

    # Returns whether the +value+ is not surrounded by double quotes.
    #
    # @example Returns +true+ when value is not quoted.
    #    unquoted?("apoptotic process")
    #    # => true
    # @example Returns +false+ when value is quoted.
    #    unquoted?("\"vesicle fusion with \"Golgi apparatus\"")
    #    # => false
    #
    # @parameter [#to_s]   value to test
    # @return    [Boolean] +true+ if +value+ is not quoted, +false+ if
    #            +value+ is quoted
    def unquoted?(value)
      !quoted?(value)
    end

    # Returns whether the +value+ represents an identifier. An
    # identifier consists of only word characters (e.g. [0-9A-Za-z_]).
    #
    # @example Returns +true+ when representing an identifier.
    #    identifier_value?("AKT1_HUMAN")
    #    # => true
    # @example Returns +false+ when not representing an identifier.
    #    identifier_value?("apoptotic process")
    #    # => false
    #
    # @parameter [#to_s]   value to test
    # @return    [Boolean] +true+ if +value+ is an identifier,
    #            +false+ if +value+ is not an identifier
    def identifier_value?(value)
      string = value.to_s
      [NonWordMatcher, KeywordMatcher].none? do |matcher|
        matcher.match string
      end
    end

    # Returns whether the +value+ represents a string value. A string
    # value consists of at least one non-word character
    # (e.g. [^0-9A-Za-z_]).
    #
    # @example Returns +true+ when representing a string value.
    #    string_value?("apoptotic process")
    #    # => true
    # @example Returns +false+ when not representing a string value.
    #    string_value?("AKT1_HUMAN")
    #    # => false
    #
    # @parameter [#to_s]   value to test
    # @return    [Boolean] +true+ if +value+ is a string value,
    #            +false+ if +value+ is not a string value
    def string_value?(value)
      string = value.to_s
      [NonWordMatcher, KeywordMatcher].any? do |matcher|
        matcher.match string
      end
    end
  end
end

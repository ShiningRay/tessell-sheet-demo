# Spreadsheet value model, formula lexer/parser and lazy evaluator.
#
# Supported syntax:
#   numbers, "strings", TRUE/FALSE, A1 references, A1:B3 ranges (function args)
#   + - * / ^ % & comparisons (= <> < <= > >=), parentheses
#   SUM AVERAGE MIN MAX COUNT COUNTA IF IFERROR ROUND ABS SQRT CONCAT AND OR NOT
#
# Errors are values, not exceptions: #VALUE!, #REF!, #DIV/0!, #NUM!, #NAME?,
# #PARSE!, #CYCLE!.

module SheetDemo
  enum CellError
    Value
    Ref
    DivZero
    Num
    Name
    Parse
    Cycle

    def label : String
      case self
      when Value   then "#VALUE!"
      when Ref     then "#REF!"
      when DivZero then "#DIV/0!"
      when Num     then "#NUM!"
      when Name    then "#NAME?"
      when Parse   then "#PARSE!"
      when Cycle   then "#CYCLE!"
      else              "#VALUE!"
      end
    end
  end

  struct CellValue
    enum Kind
      Empty
      Number
      Text
      Bool
      Error
    end

    getter kind : Kind
    getter number : Float64
    getter text : String
    getter boolean : Bool
    getter error : CellError

    def initialize(@kind : Kind, @number : Float64 = 0.0, @text : String = "",
                   @boolean : Bool = false, @error : CellError = CellError::Value)
    end

    def self.empty : CellValue
      new(Kind::Empty)
    end

    def self.number(value : Float64) : CellValue
      new(Kind::Number, number: value)
    end

    def self.text(value : String) : CellValue
      new(Kind::Text, text: value)
    end

    def self.bool(value : Bool) : CellValue
      new(Kind::Bool, boolean: value)
    end

    def self.error(value : CellError) : CellValue
      new(Kind::Error, error: value)
    end

    def empty? : Bool
      @kind == Kind::Empty
    end

    def number? : Bool
      @kind == Kind::Number
    end

    def text? : Bool
      @kind == Kind::Text
    end

    def bool? : Bool
      @kind == Kind::Bool
    end

    def error? : Bool
      @kind == Kind::Error
    end

    def display : String
      case @kind
      when Kind::Empty  then ""
      when Kind::Number then self.class.format_number(@number)
      when Kind::Text   then @text
      when Kind::Bool   then @boolean ? "TRUE" : "FALSE"
      when Kind::Error  then @error.label
      else                   ""
      end
    end

    # Numeric coercion used by arithmetic: empty behaves like zero.
    def numeric_or_zero : Float64?
      case @kind
      when Kind::Empty  then 0.0
      when Kind::Number then @number
      when Kind::Bool   then @boolean ? 1.0 : 0.0
      else                   nil
      end
    end

    def truthy? : Bool
      case @kind
      when Kind::Empty  then false
      when Kind::Number then @number != 0.0
      when Kind::Bool   then @boolean
      when Kind::Text   then !@text.empty?
      else                   false
      end
    end

    def ==(other : CellValue) : Bool
      return false unless @kind == other.kind
      case @kind
      when Kind::Empty  then true
      when Kind::Number then @number == other.number
      when Kind::Text   then @text == other.text
      when Kind::Bool   then @boolean == other.boolean
      when Kind::Error  then @error == other.error
      else                   false
      end
    end

    def self.format_number(value : Float64) : String
      return "0" if value == 0.0
      if value == value.round && value.abs < 1.0e15
        return value.to_i64.to_s
      end
      text = sprintf("%.6f", value)
      text = text.rstrip('0').rstrip('.')
      text.empty? ? "0" : text
    end
  end

  module Formula
    class ParseError < Exception
    end

    # The evaluator only needs these four operations from a sheet.
    module SheetLike
      abstract def raw(row : Int32, col : Int32) : String
      abstract def value(row : Int32, col : Int32) : CellValue
      abstract def row_count : Int32
      abstract def col_count : Int32

      def in_bounds?(row : Int32, col : Int32) : Bool
        row >= 0 && col >= 0 && row < row_count && col < col_count
      end
    end

    enum BinaryOp
      Add
      Sub
      Mul
      Div
      Pow
      Concat
      Eq
      Ne
      Lt
      Le
      Gt
      Ge
    end

    abstract class Expr
      abstract def eval(ev : Evaluator) : CellValue
    end

    class LiteralExpr < Expr
      getter value : CellValue

      def initialize(@value : CellValue)
      end

      def eval(ev : Evaluator) : CellValue
        @value
      end
    end

    class RefExpr < Expr
      getter row : Int32
      getter col : Int32

      def initialize(@row : Int32, @col : Int32)
      end

      def eval(ev : Evaluator) : CellValue
        return CellValue.error(CellError::Ref) unless ev.sheet.in_bounds?(@row, @col)
        ev.sheet.value(@row, @col)
      end
    end

    class RangeExpr < Expr
      getter row0 : Int32
      getter col0 : Int32
      getter row1 : Int32
      getter col1 : Int32

      def initialize(row0 : Int32, col0 : Int32, row1 : Int32, col1 : Int32)
        @row0 = Math.min(row0, row1)
        @row1 = Math.max(row0, row1)
        @col0 = Math.min(col0, col1)
        @col1 = Math.max(col0, col1)
      end

      def eval(ev : Evaluator) : CellValue
        CellValue.error(CellError::Value)
      end

      # Append every cell in row-major order. Returns an error on out-of-bounds.
      def collect(ev : Evaluator, sink : Array(CellValue)) : CellError?
        unless ev.sheet.in_bounds?(@row0, @col0) && ev.sheet.in_bounds?(@row1, @col1)
          return CellError::Ref
        end
        row = @row0
        while row <= @row1
          col = @col0
          while col <= @col1
            sink << ev.sheet.value(row, col)
            col += 1
          end
          row += 1
        end
        nil
      end
    end

    class UnaryExpr < Expr
      getter op : Char
      getter operand : Expr

      def initialize(@op : Char, @operand : Expr)
      end

      def eval(ev : Evaluator) : CellValue
        value = @operand.eval(ev)
        return value if value.error?
        number = value.numeric_or_zero
        return CellValue.error(CellError::Value) unless number
        case @op
        when '-' then CellValue.number(-number)
        else          CellValue.number(number)
        end
      end
    end

    class PercentExpr < Expr
      getter operand : Expr

      def initialize(@operand : Expr)
      end

      def eval(ev : Evaluator) : CellValue
        value = @operand.eval(ev)
        return value if value.error?
        number = value.numeric_or_zero
        return CellValue.error(CellError::Value) unless number
        CellValue.number(number / 100.0)
      end
    end

    class BinaryExpr < Expr
      getter op : BinaryOp
      getter left : Expr
      getter right : Expr

      def initialize(@op : BinaryOp, @left : Expr, @right : Expr)
      end

      def eval(ev : Evaluator) : CellValue
        lhs = @left.eval(ev)
        return lhs if lhs.error?
        rhs = @right.eval(ev)
        return rhs if rhs.error?

        case @op
        when BinaryOp::Concat
          return CellValue.text(lhs.display + rhs.display)
        when BinaryOp::Eq, BinaryOp::Ne, BinaryOp::Lt, BinaryOp::Le, BinaryOp::Gt, BinaryOp::Ge
          return compare(lhs, rhs)
        else
          a = lhs.numeric_or_zero
          b = rhs.numeric_or_zero
          return CellValue.error(CellError::Value) unless a && b
          case @op
          when BinaryOp::Add then CellValue.number(a + b)
          when BinaryOp::Sub then CellValue.number(a - b)
          when BinaryOp::Mul then CellValue.number(a * b)
          when BinaryOp::Div
            return CellValue.error(CellError::DivZero) if b == 0.0
            CellValue.number(a / b)
          when BinaryOp::Pow
            result = a ** b
            result.finite? ? CellValue.number(result) : CellValue.error(CellError::Num)
          else
            CellValue.error(CellError::Value)
          end
        end
      end

      private def compare(lhs : CellValue, rhs : CellValue) : CellValue
        cmp : Int32
        if lhs.number? || rhs.number? || lhs.empty? || rhs.empty? ||
           lhs.bool? || rhs.bool?
          a = lhs.numeric_or_zero
          b = rhs.numeric_or_zero
          return CellValue.error(CellError::Value) unless a && b
          cmp = (a <=> b) || 0
        elsif lhs.text? && rhs.text?
          cmp = lhs.text <=> rhs.text
        elsif lhs.empty? && rhs.text?
          cmp = "" <=> rhs.text
        elsif lhs.text? && rhs.empty?
          cmp = lhs.text <=> ""
        else
          return CellValue.error(CellError::Value)
        end
        case @op
        when BinaryOp::Eq then CellValue.bool(cmp == 0)
        when BinaryOp::Ne then CellValue.bool(cmp != 0)
        when BinaryOp::Lt then CellValue.bool(cmp < 0)
        when BinaryOp::Le then CellValue.bool(cmp <= 0)
        when BinaryOp::Gt then CellValue.bool(cmp > 0)
        when BinaryOp::Ge then CellValue.bool(cmp >= 0)
        else                   CellValue.error(CellError::Value)
        end
      end
    end

    class NameExpr < Expr
      getter name : String

      def initialize(@name : String)
      end

      def eval(ev : Evaluator) : CellValue
        CellValue.error(CellError::Name)
      end
    end

    class FuncExpr < Expr
      getter name : String
      getter args : Array(Expr)

      def initialize(@name : String, @args : Array(Expr))
      end

      def eval(ev : Evaluator) : CellValue
        name = @name.upcase
        case name
        when "IF"
          return CellValue.error(CellError::Value) if @args.size < 2 || @args.size > 3
          condition = @args[0].eval(ev)
          return condition if condition.error?
          branch = condition.truthy? ? @args[1] : (@args[2]? || LiteralExpr.new(CellValue.empty))
          return branch.eval(ev)
        when "IFERROR"
          return CellValue.error(CellError::Value) unless @args.size == 2
          value = @args[0].eval(ev)
          return value unless value.error?
          return @args[1].eval(ev)
        end

        values = [] of CellValue
        @args.each do |arg|
          if arg.is_a?(RangeExpr)
            if error = arg.collect(ev, values)
              return CellValue.error(error)
            end
          else
            value = arg.eval(ev)
            return value if value.error?
            values << value
          end
        end
        # Range errors are values too; propagate the first one.
        values.each do |value|
          return value if value.error?
        end

        case name
        when "SUM" then number_result(values.sum { |v| v.number? ? v.number : 0.0 })
        when "AVERAGE", "AVG"
          numbers = numeric_values(values)
          return CellValue.error(CellError::DivZero) if numbers.empty?
          number_result(numbers.sum / numbers.size)
        when "MIN"    then number_result(numbers_or_zero(values).min? || 0.0)
        when "MAX"    then number_result(numbers_or_zero(values).max? || 0.0)
        when "COUNT"  then CellValue.number(values.count(&.number?).to_f64)
        when "COUNTA" then CellValue.number(values.count { |v| !v.empty? }.to_f64)
        when "ROUND"
          return CellValue.error(CellError::Value) if values.size != 2
          number = values[0].numeric_or_zero
          digits = values[1].numeric_or_zero
          return CellValue.error(CellError::Value) unless number && digits
          CellValue.number(number.round(digits.to_i))
        when "ABS"
          return CellValue.error(CellError::Value) unless values.size == 1
          number = values[0].numeric_or_zero
          return CellValue.error(CellError::Value) unless number
          CellValue.number(number.abs)
        when "SQRT"
          return CellValue.error(CellError::Value) unless values.size == 1
          number = values[0].numeric_or_zero
          return CellValue.error(CellError::Value) unless number
          return CellValue.error(CellError::Num) if number < 0.0
          CellValue.number(Math.sqrt(number))
        when "CONCAT"
          CellValue.text(values.map(&.display).join)
        when "AND"
          return CellValue.error(CellError::Value) if values.empty?
          CellValue.bool(values.all?(&.truthy?))
        when "OR"
          return CellValue.error(CellError::Value) if values.empty?
          CellValue.bool(values.any?(&.truthy?))
        when "NOT"
          return CellValue.error(CellError::Value) unless values.size == 1
          CellValue.bool(!values[0].truthy?)
        else
          CellValue.error(CellError::Name)
        end
      end

      private def numeric_values(values : Array(CellValue)) : Array(Float64)
        result = [] of Float64
        values.each { |v| result << v.number if v.number? }
        result
      end

      private def numbers_or_zero(values : Array(CellValue)) : Array(Float64)
        result = [] of Float64
        values.each { |v| result << v.number if v.number? }
        result
      end

      private def number_result(value : Float64) : CellValue
        value.finite? ? CellValue.number(value) : CellValue.error(CellError::Num)
      end
    end

    struct Token
      enum Kind
        Number
        String
        Ident
        Plus
        Minus
        Star
        Slash
        Caret
        Percent
        LParen
        RParen
        Comma
        Colon
        Eq
        Ne
        Lt
        Le
        Gt
        Ge
        Amp
        Eof
      end

      getter kind : Kind
      getter text : String
      getter number : Float64
      getter pos : Int32

      def initialize(@kind : Kind, @text : String = "", @number : Float64 = 0.0,
                     @pos : Int32 = 0)
      end
    end

    class Lexer
      @chars : Array(Char)
      @index : Int32

      def self.tokenize(source : String) : Array(Token)
        new(source).tokenize
      end

      def initialize(source : String)
        @chars = source.chars
        @index = 0
      end

      def tokenize : Array(Token)
        tokens = [] of Token
        loop do
          skip_whitespace
          break if eof?
          char = peek
          case char
          when '+'
            add(tokens, Token::Kind::Plus, "+")
          when '-'
            add(tokens, Token::Kind::Minus, "-")
          when '*'
            add(tokens, Token::Kind::Star, "*")
          when '/'
            add(tokens, Token::Kind::Slash, "/")
          when '^'
            add(tokens, Token::Kind::Caret, "^")
          when '%'
            add(tokens, Token::Kind::Percent, "%")
          when '('
            add(tokens, Token::Kind::LParen, "(")
          when ')'
            add(tokens, Token::Kind::RParen, ")")
          when ','
            add(tokens, Token::Kind::Comma, ",")
          when ':'
            add(tokens, Token::Kind::Colon, ":")
          when '&'
            add(tokens, Token::Kind::Amp, "&")
          when '='
            add(tokens, Token::Kind::Eq, "=")
          when '<'
            @index += 1
            if peek?('=')
              @index += 1
              tokens << Token.new(Token::Kind::Le, "<=", 0.0, @index - 2)
            elsif peek?('>')
              @index += 1
              tokens << Token.new(Token::Kind::Ne, "<>", 0.0, @index - 2)
            else
              tokens << Token.new(Token::Kind::Lt, "<", 0.0, @index - 1)
            end
          when '>'
            @index += 1
            if peek?('=')
              @index += 1
              tokens << Token.new(Token::Kind::Ge, ">=", 0.0, @index - 2)
            else
              tokens << Token.new(Token::Kind::Gt, ">", 0.0, @index - 1)
            end
          when '"'
            tokens << read_string
          when '0'..'9', '.'
            tokens << read_number
          when 'A'..'Z', 'a'..'z', '_', '$'
            tokens << read_identifier
          else
            raise ParseError.new("unexpected character #{char.inspect} at #{@index}")
          end
        end
        tokens << Token.new(Token::Kind::Eof, "", 0.0, @index)
        tokens
      end

      private def add(tokens : Array(Token), kind : Token::Kind, text : String) : Nil
        start = @index
        @index += 1
        tokens << Token.new(kind, text, 0.0, start)
      end

      private def read_string : Token
        start = @index
        @index += 1
        builder = String::Builder.new
        loop do
          raise ParseError.new("unterminated string at #{start}") if eof?
          char = @chars[@index]
          @index += 1
          if char == '"'
            if peek?('"')
              @index += 1
              builder << '"'
            else
              break
            end
          else
            builder << char
          end
        end
        Token.new(Token::Kind::String, builder.to_s, 0.0, start)
      end

      private def read_number : Token
        start = @index
        builder = String::Builder.new
        seen_dot = false
        while !eof?
          char = peek
          if char.ascii_number?
            builder << char
            @index += 1
          elsif char == '.' && !seen_dot
            seen_dot = true
            builder << char
            @index += 1
          elsif char == 'e' || char == 'E'
            builder << char
            @index += 1
            if !eof? && (peek == '+' || peek == '-')
              builder << peek
              @index += 1
            end
          else
            break
          end
        end
        text = builder.to_s
        value = text.to_f64?
        raise ParseError.new("invalid number #{text.inspect} at #{start}") unless value
        Token.new(Token::Kind::Number, text, value, start)
      end

      private def read_identifier : Token
        start = @index
        builder = String::Builder.new
        while !eof?
          char = peek
          if char.ascii_letter? || char.ascii_number? || char == '_' || char == '$' || char == '.'
            builder << char
            @index += 1
          else
            break
          end
        end
        Token.new(Token::Kind::Ident, builder.to_s, 0.0, start)
      end

      private def skip_whitespace : Nil
        while !eof? && peek.ascii_whitespace?
          @index += 1
        end
      end

      private def eof? : Bool
        @index >= @chars.size
      end

      private def peek : Char
        @chars[@index]
      end

      private def peek?(char : Char) : Bool
        !eof? && @chars[@index] == char
      end
    end

    class Parser
      @tokens : Array(Token)
      @index : Int32

      def initialize(@tokens : Array(Token))
        @index = 0
      end

      def parse : Expr
        expr = parse_comparison
        unless current.kind == Token::Kind::Eof
          raise ParseError.new("unexpected token #{current.text.inspect} at #{current.pos}")
        end
        expr
      end

      private def parse_comparison : Expr
        expr = parse_additive
        while op = comparison_op(current.kind)
          advance
          right = parse_additive
          expr = BinaryExpr.new(op, expr, right)
        end
        expr
      end

      private def comparison_op(kind : Token::Kind) : BinaryOp?
        case kind
        when Token::Kind::Eq then BinaryOp::Eq
        when Token::Kind::Ne then BinaryOp::Ne
        when Token::Kind::Lt then BinaryOp::Lt
        when Token::Kind::Le then BinaryOp::Le
        when Token::Kind::Gt then BinaryOp::Gt
        when Token::Kind::Ge then BinaryOp::Ge
        else                      nil
        end
      end

      private def parse_additive : Expr
        expr = parse_multiplicative
        loop do
          op = case current.kind
               when Token::Kind::Plus  then BinaryOp::Add
               when Token::Kind::Minus then BinaryOp::Sub
               else                         nil
               end
          break unless op
          advance
          expr = BinaryExpr.new(op, expr, parse_multiplicative)
        end
        expr
      end

      private def parse_multiplicative : Expr
        expr = parse_unary
        loop do
          op = case current.kind
               when Token::Kind::Star  then BinaryOp::Mul
               when Token::Kind::Slash then BinaryOp::Div
               when Token::Kind::Amp   then BinaryOp::Concat
               else                         nil
               end
          break unless op
          advance
          expr = BinaryExpr.new(op, expr, parse_unary)
        end
        expr
      end

      private def parse_unary : Expr
        if current.kind == Token::Kind::Minus || current.kind == Token::Kind::Plus
          op = current.text[0]
          advance
          return UnaryExpr.new(op, parse_unary)
        end
        parse_power
      end

      private def parse_power : Expr
        expr = parse_postfix
        if current.kind == Token::Kind::Caret
          advance
          expr = BinaryExpr.new(BinaryOp::Pow, expr, parse_unary)
        end
        expr
      end

      private def parse_postfix : Expr
        expr = parse_primary
        while current.kind == Token::Kind::Percent
          advance
          expr = PercentExpr.new(expr)
        end
        expr
      end

      private def parse_primary : Expr
        token = current
        case token.kind
        when Token::Kind::Number
          advance
          LiteralExpr.new(CellValue.number(token.number))
        when Token::Kind::String
          advance
          LiteralExpr.new(CellValue.text(token.text))
        when Token::Kind::Ident
          parse_identifier
        when Token::Kind::LParen
          advance
          expr = parse_comparison
          expect(Token::Kind::RParen)
          expr
        else
          raise ParseError.new("unexpected token #{token.text.inspect} at #{token.pos}")
        end
      end

      private def parse_identifier : Expr
        token = current
        advance
        name = token.text
        if current.kind == Token::Kind::LParen
          advance
          args = [] of Expr
          unless current.kind == Token::Kind::RParen
            loop do
              args << parse_arg
              break unless current.kind == Token::Kind::Comma
              advance
            end
          end
          expect(Token::Kind::RParen)
          return FuncExpr.new(name, args)
        end
        upper = name.upcase
        return LiteralExpr.new(CellValue.bool(true)) if upper == "TRUE"
        return LiteralExpr.new(CellValue.bool(false)) if upper == "FALSE"
        if ref = Formula.cell_ref(name)
          return RefExpr.new(ref[0], ref[1])
        end
        NameExpr.new(name)
      end

      private def parse_arg : Expr
        first = parse_comparison
        if current.kind == Token::Kind::Colon
          advance
          start = first.as?(RefExpr)
          raise ParseError.new("range must start with a cell reference") unless start
          finish_expr = parse_comparison
          finish = finish_expr.as?(RefExpr)
          raise ParseError.new("range must end with a cell reference") unless finish
          return RangeExpr.new(start.row, start.col, finish.row, finish.col)
        end
        first
      end

      private def expect(kind : Token::Kind) : Nil
        unless current.kind == kind
          raise ParseError.new("expected #{kind}, got #{current.kind} at #{current.pos}")
        end
        advance
      end

      private def current : Token
        @tokens[@index]
      end

      private def advance : Nil
        @index += 1 if @index < @tokens.size - 1
      end
    end

    NUMBER_RE   = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/
    CELL_REF_RE = /\A([A-Za-z]{1,3})([1-9][0-9]*)\z/

    def self.numeric_literal?(text : String) : Float64?
      return nil unless text.matches?(NUMBER_RE)
      text.to_f64?
    end

    def self.cell_ref(text : String) : {Int32, Int32}?
      cleaned = text.delete('$')
      match = CELL_REF_RE.match(cleaned)
      return nil unless match
      col = 0
      match[1].upcase.each_char do |char|
        col = col * 26 + (char.ord - 'A'.ord + 1)
      end
      {match[2].to_i - 1, col - 1}
    end

    def self.col_label(col : Int32) : String
      return "?" if col < 0
      value = col + 1
      builder = String::Builder.new
      chars = [] of Char
      while value > 0
        value -= 1
        chars << ('A'.ord + value % 26).unsafe_chr
        value //= 26
      end
      chars.reverse_each { |char| builder << char }
      builder.to_s
    end

    class Evaluator
      getter sheet : SheetLike

      @cache : Hash(Int32, CellValue)
      @evaluating : Set(Int32)
      @asts : Hash(String, Expr?)

      def initialize(@sheet : SheetLike)
        @cache = Hash(Int32, CellValue).new
        @evaluating = Set(Int32).new
        @asts = Hash(String, Expr?).new
      end

      def reset_cache : Nil
        @cache.clear
        @evaluating.clear
      end

      def cell_value(row : Int32, col : Int32) : CellValue
        return CellValue.error(CellError::Ref) unless @sheet.in_bounds?(row, col)
        key = row * @sheet.col_count + col
        if cached = @cache[key]?
          return cached
        end
        if @evaluating.includes?(key)
          return CellValue.error(CellError::Cycle)
        end
        @evaluating << key
        value = evaluate_raw(@sheet.raw(row, col))
        @evaluating.delete(key)
        @cache[key] = value
        value
      end

      def evaluate_raw(raw : String) : CellValue
        return CellValue.empty if raw.empty?
        if raw.starts_with?("'")
          return CellValue.text(raw.byte_slice(1, raw.bytesize - 1))
        end
        if raw.starts_with?("=")
          source = raw.byte_slice(1, raw.bytesize - 1)
          expr = parse(source)
          return CellValue.error(CellError::Parse) unless expr
          return expr.eval(self)
        end
        if number = Formula.numeric_literal?(raw)
          return CellValue.number(number)
        end
        CellValue.text(raw)
      end

      private def parse(source : String) : Expr?
        if @asts.has_key?(source)
          return @asts[source]
        end
        expr = begin
          tokens = Lexer.tokenize(source)
          Parser.new(tokens).parse
        rescue ParseError
          nil
        end
        @asts[source] = expr
        expr
      end
    end
  end
end

require "./spec_helper"

describe "SheetDemo::Formula" do
  it "parses A1 references and column labels round-trip" do
    SheetDemo::Formula.cell_ref("A1").should eq({0, 0})
    SheetDemo::Formula.cell_ref("$B$12").should eq({11, 1})
    SheetDemo::Formula.cell_ref("AA10").should eq({9, 26})
    SheetDemo::Formula.col_label(0).should eq("A")
    SheetDemo::Formula.col_label(25).should eq("Z")
    SheetDemo::Formula.col_label(26).should eq("AA")
  end

  it "rejects malformed references" do
    SheetDemo::Formula.cell_ref("A0").should be_nil
    SheetDemo::Formula.cell_ref("1A").should be_nil
    SheetDemo::Formula.cell_ref("A").should be_nil
  end

  it "detects numeric literals only" do
    SheetDemo::Formula.numeric_literal?("42").should eq(42.0)
    SheetDemo::Formula.numeric_literal?("-3.5e2").should eq(-350.0)
    SheetDemo::Formula.numeric_literal?("12abc").should be_nil
    SheetDemo::Formula.numeric_literal?("").should be_nil
  end
end

describe "SheetDemo::Formula::Lexer" do
  it "tokenizes numbers, strings, refs and operators" do
    tokens = SheetDemo::Formula::Lexer.tokenize(%(SUM(A1:B2, "x") * -3))
    tokens.map(&.kind).should eq([
      SheetDemo::Formula::Token::Kind::Ident,
      SheetDemo::Formula::Token::Kind::LParen,
      SheetDemo::Formula::Token::Kind::Ident,
      SheetDemo::Formula::Token::Kind::Colon,
      SheetDemo::Formula::Token::Kind::Ident,
      SheetDemo::Formula::Token::Kind::Comma,
      SheetDemo::Formula::Token::Kind::String,
      SheetDemo::Formula::Token::Kind::RParen,
      SheetDemo::Formula::Token::Kind::Star,
      SheetDemo::Formula::Token::Kind::Minus,
      SheetDemo::Formula::Token::Kind::Number,
      SheetDemo::Formula::Token::Kind::Eof,
    ])
  end

  it "handles escaped quotes and comparison tokens" do
    tokens = SheetDemo::Formula::Lexer.tokenize(%("a""b" <> 1 >= 2))
    tokens[0].text.should eq("a\"b")
    tokens[1].kind.should eq(SheetDemo::Formula::Token::Kind::Ne)
    tokens[3].kind.should eq(SheetDemo::Formula::Token::Kind::Ge)
  end

  it "raises on unterminated strings" do
    expect_raises(SheetDemo::Formula::ParseError) do
      SheetDemo::Formula::Lexer.tokenize(%("abc))
    end
  end
end

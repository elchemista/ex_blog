defmodule ExBlog.Agent.LanguageTest do
  use ExUnit.Case, async: true

  alias ExBlog.Agent.Language

  test "parses configured codes and English language names" do
    supported = ["it", "en"]

    assert Language.parse("en", supported) == {:ok, "en"}
    assert Language.parse("English", supported) == {:ok, "en"}
    assert Language.parse("write it in English, please", supported) == {:ok, "en"}
    assert Language.parse("Italian", supported) == {:ok, "it"}
    assert Language.parse("use Italian", supported) == {:ok, "it"}
  end

  test "rejects names and codes that are not configured" do
    assert Language.parse("French", ["it", "en"]) == :error
    assert Language.parse("fr", ["it", "en"]) == :error
    assert Language.parse("italiano", ["it", "en"]) == :error
  end

  test "resolves regional languages only when their base is unambiguous" do
    assert Language.parse("Portuguese", ["pt-BR", "en"]) == {:ok, "pt-BR"}
    assert Language.parse("Portuguese", ["pt-BR", "pt-PT"]) == :error
    assert Language.parse("pt-BR", ["pt-BR", "pt-PT"]) == {:ok, "pt-BR"}
  end

  test "extracts a target language without confusing the English pronoun it" do
    supported = ["it", "en"]

    assert Language.parse_target("translate it to English", supported) == {:ok, "en"}
    assert Language.parse_target("translate it to en please", supported) == {:ok, "en"}
  end
end

defmodule ExBlog.Telegram.QRTest do
  use ExUnit.Case, async: true

  alias ExBlog.Telegram.QR

  test "renders a bounded responsive SVG without embedding the login link" do
    login_link = "tg://login?token=short-lived-secret"

    assert {:ok, svg} = QR.render(login_link)
    assert svg =~ ~s(viewBox="0 0 )
    assert svg =~ ~s(width="100%")
    assert svg =~ ~s(height="100%")
    refute svg =~ login_link
  end

  test "rejects invalid and oversized payloads" do
    assert {:error, :empty_payload} = QR.render("   ")
    assert {:error, :invalid_payload} = QR.render(nil)
    assert {:error, :invalid_payload} = QR.render(String.duplicate("x", 4_097))
  end
end

defmodule ExBlog.Admin.LoginThrottleTest do
  use ExUnit.Case, async: false

  alias ExBlog.Admin.LoginThrottle

  test "blocks a requester after five failures and can be reset" do
    requester = {:test_requester, make_ref()}

    for _attempt <- 1..5 do
      assert :ok = LoginThrottle.allow_attempt(requester)
    end

    assert {:error, retry_after} = LoginThrottle.allow_attempt(requester)
    assert retry_after > 0

    assert :ok = LoginThrottle.reset(requester)
    assert :ok = LoginThrottle.allow_attempt(requester)
  end
end
